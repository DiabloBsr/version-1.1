from pathlib import Path
from dotenv import load_dotenv
import os

BASE_DIR = Path('.').resolve()
env = BASE_DIR / '.env'
print("env ->", env)
load_dotenv(dotenv_path=env)
print("exists ->", env.exists())
for k in ["DB_NAME","DB_USER","DB_PASSWORD","DB_HOST","DB_PORT","FERNET_KEY","SECRET_KEY"]:
    print(f"{k} = {repr(os.getenv(k))}")