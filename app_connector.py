# ===============================================================================
# AI APPLICATION CONNECTOR (Python Example)
# This script demonstrates how an external application connects to the PostgreSQL
# database and uses the 'ai_command_translator' function (our custom language)
# to load the LLM parameters efficiently.
#
# NOTE: This requires the 'psycopg2-binary' library to be installed.
# NOTE: The database connection string must be configured for your local PostgreSQL instance.
# ===============================================================================

import psycopg2
from psycopg2 import sql
import time
import os
from typing import List, Tuple

# --- Configuration for your PostgreSQL instance ---
DB_HOST = "localhost"
DB_NAME = "ai_storage_db"
DB_USER = "postgres"
DB_PASSWORD = "your_strong_password"
DB_PORT = 5432

# --- Custom AI Commands (Our Byte-Level Language Concept) ---
# In a real system, these would be compact byte codes, but we use integers here.
COMMAND_LOAD_MODEL = 1
COMMAND_GET_STATUS = 2 # Placeholder for future commands

# --- Simulation Constants ---
# Assuming we want to load the model stored under file_id 1
LLM_MODEL_ID = 1 
# Output file where the reconstructed model data will be written
OUTPUT_MODEL_FILE = "reconstructed_llm_parameters.bin" 

def connect_db():
    """Establishes and returns a database connection."""
    print(f"Connecting to PostgreSQL database '{DB_NAME}'...")
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port=DB_PORT
        )
        print("Database connection successful.")
        return conn
    except psycopg2.Error as e:
        print(f"Error connecting to database: {e}")
        # In a real app, you would handle connection failure gracefully
        raise

def load_and_reconstruct_llm(conn: psycopg2.connect, model_id: int):
    """
    Executes the custom AI command to retrieve and reconstruct the LLM parameters.
    This demonstrates the speed and simplicity of the AI's custom language interface.
    """
    print(f"\n[AI COMMAND] Issuing command code {COMMAND_LOAD_MODEL} to database...")
    
    # 1. Execute the custom PL/pgSQL Translator function
    # The application sends a simple command, and the DB executes the complex JOIN logic.
    query = sql.SQL("SELECT parameter_content FROM ai_command_translator(%s, %s)")
    
    start_time = time.time()
    total_bytes = 0
    
    with conn.cursor() as cur:
        # 2. Execute the function call
        cur.execute(query, [model_id, COMMAND_LOAD_MODEL])

        # 3. Stream the massive data blocks and reconstruct the file
        print(f"Starting retrieval and reconstruction for Model ID {model_id}...")
        
        with open(OUTPUT_MODEL_FILE, "wb") as f:
            # Fetch one row (which contains one parameter block) at a time
            # and write it to the output file.
            while True:
                # The fetchmany() method is used for efficient streaming of large results
                rows = cur.fetchmany(size=1000) 
                if not rows:
                    break
                
                for row in rows:
                    # 'row[0]' is the BYTEA data retrieved from the Parameter_Dictionary
                    parameter_content = row[0] 
                    f.write(parameter_content)
                    total_bytes += len(parameter_content)
            
    end_time = time.time()
    
    # 4. Report Results
    print("\n--- Reconstruction Complete ---")
    print(f"File: {OUTPUT_MODEL_FILE}")
    print(f"Total time taken: {end_time - start_time:.4f} seconds")
    print(f"Total parameters (bytes) reconstructed: {total_bytes / (1024*1024):.2f} MB (Simulated)")
    print(f"Database interface successfully managed {total_bytes} bytes of complex data.")

def main():
    """Main execution function."""
    if os.path.exists(OUTPUT_MODEL_FILE):
        os.remove(OUTPUT_MODEL_FILE)
    
    conn = None
    try:
        conn = connect_db()
        # Ensure autocommit is off to manage transactions if needed, though simple SELECT is fine.
        conn.autocommit = True 
        
        # --- EXECUTE THE CORE TASK ---
        # Note: You must first ensure that the database schema is loaded 
        # (using system_setup.sql) and the file with model_id=1 exists.
        load_and_reconstruct_llm(conn, LLM_MODEL_ID)

    except Exception as e:
        print(f"\n[FATAL ERROR] System execution failed: {e}")
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    main()
