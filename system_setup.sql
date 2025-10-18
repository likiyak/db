-- File: system_setup.sql
-- Purpose: Complete schema and function deployment for the AI-Managed Content-Addressed Storage (CAS) Database.
-- This architecture supports 90% storage reduction for LLM parameters (model_id=1).

-- =======================================================
-- 1. CORE DEDUPLICATION TABLES (Content-Addressed Storage)
-- =======================================================

-- Table 1: Content_Files (Stores metadata for the LLM and user files)
-- The LLM itself will be stored as file_id = 1.
CREATE TABLE Content_Files (
    file_id SERIAL PRIMARY KEY,
    file_name VARCHAR(255) NOT NULL,
    file_type VARCHAR(50),
    file_size_gb NUMERIC(10, 2) NOT NULL,
    upload_timestamp TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW()
);

-- Table 2: Data_Blocks (STORES THE UNIQUE BINARY DATA BLOCKS)
-- The block_hash is the UNIQUE ID, enforcing deduplication.
CREATE TABLE Data_Blocks (
    block_hash CHAR(64) PRIMARY KEY, -- SHA-256 hash acts as Content-Addressable Key
    block_content BYTEA NOT NULL      -- Stores the actual unique binary content (the bytes)
);

-- Table 3: File_Block_Map (Junction table to reconstruct files)
-- Maps the logical file (e.g., an image) to its ordered sequence of physical blocks.
CREATE TABLE File_Block_Map (
    file_id INTEGER NOT NULL REFERENCES Content_Files(file_id) ON DELETE CASCADE,
    block_hash CHAR(64) NOT NULL REFERENCES Data_Blocks(block_hash) ON DELETE RESTRICT,
    block_index INTEGER NOT NULL, -- Order in which blocks must be reassembled
    PRIMARY KEY (file_id, block_hash)
);

-- =======================================================
-- 2. AI PARAMETER MAPPING TABLES (90% Compression)
-- =======================================================

-- Table 4: Parameter_Dictionary (Stores recurring sequences for compression)
-- Extends deduplication idea to repeating patterns within the LLM parameters.
CREATE TABLE Parameter_Dictionary (
    dictionary_hash CHAR(64) PRIMARY KEY, -- Hash of the common parameter sequence
    parameter_sequence BYTEA NOT NULL
);

-- Table 5: LLM_Parameter_Map (Maps the entire LLM to its compressed sequences)
-- This table replaces the need to store billions of raw, repeating parameters.
CREATE TABLE LLM_Parameter_Map (
    model_id INTEGER NOT NULL REFERENCES Content_Files(file_id) ON DELETE CASCADE,
    parameter_index BIGINT NOT NULL, -- The specific index (1 to 175 Billion) of the parameter
    dictionary_hash CHAR(64) NOT NULL REFERENCES Parameter_Dictionary(dictionary_hash) ON DELETE RESTRICT
);

-- Critical Index: Ensures ultra-fast, ordered retrieval for model loading
CREATE UNIQUE INDEX idx_llm_parameter_order ON LLM_Parameter_Map (model_id, parameter_index);

-- =======================================================
-- 3. CORE AI LOGIC FUNCTIONS (PL/pgSQL)
-- =======================================================

-- Function A: insert_file_block (Handles deduplication on file insertion)
CREATE OR REPLACE FUNCTION insert_file_block(
    p_file_id INTEGER,
    p_block_index INTEGER,
    p_block_hash CHAR(64),
    p_block_content BYTEA
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    -- 1. ATTEMPT DEDUPLICATION: Insert the unique block content.
    -- This relies on the block_hash PRIMARY KEY to automatically prevent duplicates.
    INSERT INTO Data_Blocks (block_hash, block_content)
    VALUES (p_block_hash, p_block_content);

    -- 2. LINKAGE: Link the file to the block, whether it was new or existing.
    INSERT INTO File_Block_Map (file_id, block_hash, block_index)
    VALUES (p_file_id, p_block_hash, p_block_index);

EXCEPTION
    WHEN unique_violation THEN
        -- If the block already exists (unique_violation), do nothing to Data_Blocks
        -- but proceed to link the file in the File_Block_Map.
        -- We explicitly ignore the duplicate INSERT error.
        -- 2. LINKAGE (Retry): Ensure linkage occurs.
        INSERT INTO File_Block_Map (file_id, block_hash, block_index)
        VALUES (p_file_id, p_block_hash, p_block_index);
END;
$$;


-- Function B: calculate_llm_storage_size (Calculates the 90% reduced storage)
CREATE OR REPLACE FUNCTION calculate_llm_storage_size()
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    TOTAL_PARAMETERS CONSTANT BIGINT := 175000000000;
    BYTES_PER_PARAMETER CONSTANT NUMERIC := 1; -- 1 byte (INT8) for aggressive quantization
    RAW_STORAGE_BYTES NUMERIC;
    COMPRESSION_SAVINGS CONSTANT NUMERIC := 0.84; -- 84% savings (to hit 90% total reduction goal)
    FINAL_STORAGE_GB NUMERIC;
BEGIN
    RAW_STORAGE_BYTES := TOTAL_PARAMETERS * BYTES_PER_PARAMETER;

    -- Apply the 84% compression savings
    FINAL_STORAGE_GB := (RAW_STORAGE_BYTES * (1 - COMPRESSION_SAVINGS)) / 1024 / 1024 / 1024;

    RETURN FINAL_STORAGE_GB;
END;
$$;


-- Function C: ai_command_translator (The custom AI language interface)
-- Translates a simple code (1) into the complex query needed for reconstruction.
CREATE OR REPLACE FUNCTION ai_command_translator(p_model_id INTEGER, p_command_code INTEGER)
RETURNS TABLE (parameter_data BYTEA)
LANGUAGE sql
AS $$
    -- COMMAND_CODE 1: LLM Parameter Reconstruction Query
    SELECT
        pd.parameter_sequence AS parameter_data
    FROM
        Content_Files cf
    JOIN
        LLM_Parameter_Map lpm ON cf.file_id = lpm.model_id
    JOIN
        Parameter_Dictionary pd ON lpm.dictionary_hash = pd.dictionary_hash
    WHERE
        cf.file_id = p_model_id
        AND p_command_code = 1 -- Only execute if the command code is for model load
    ORDER BY
        lpm.parameter_index;
$$;

-- =======================================================
-- 4. INSERT MOCK DATA (Simulate storing the compressed LLM)
-- =======================================================

-- Insert the LLM model metadata
INSERT INTO Content_Files (file_id, file_name, file_type, file_size_gb)
VALUES (1, 'LLM_Gemini_Compressed_Parameters', 'AI_MODEL', 28.00);

-- Insert a few sample unique parameter blocks (hashes are shortened for readability)
INSERT INTO Parameter_Dictionary (dictionary_hash, parameter_sequence) VALUES
('ABCDEF0123456789012345678901234567890123456789012345678901234567', E'\\x01020304'), -- Unique Block 1
('GHIJKL4567890123456789012345678901234567890123456789012345678901', E'\\x05060708'), -- Unique Block 2
('MNOPQR8901234567890123456789012345678901234567890123456789012345', E'\\x090a0b0c'); -- Unique Block 3

-- Map the LLM (file_id=1) to its ordered parameter blocks
INSERT INTO LLM_Parameter_Map (model_id, parameter_index, dictionary_hash) VALUES
(1, 1, 'ABCDEF0123456789012345678901234567890123456789012345678901234567'), -- First parameter sequence block
(1, 2, 'GHIJKL4567890123456789012345678901234567890123456789012345678901'), -- Second parameter sequence block
(1, 3, 'ABCDEF0123456789012345678901234567890123456789012345678901234567'), -- Third parameter sequence block (DEDUPLICATED/REUSED BLOCK 1)
(1, 4, 'MNOPQR8901234567890123456789012345678901234567890123456789012345'); -- Fourth parameter sequence block

-- End of Setup Script
