import os
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import datetime

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal() # Open session for this specific request
    try:
        yield db        # Hand it to FastAPI/your endpoint
    finally:
        db.close()      # GUARANTEED to close, even if your code crashes halfway through



def record_click(db: Session, is_mocochan: bool):
    query = text("""
        INSERT INTO "baubau_table" (is_mocochan)
        VALUES (:is_mocochan)
        RETURNING id, timestamp, is_mocochan;
    """)
    result = db.execute(query, {"is_mocochan": is_mocochan})
    db.commit()
    return result.fetchone()  # Returns a Row object (tuple-like)


def get_total_clicks(db: Session):
    query = text("""SELECT count(*) from "baubau_table" """)
    result = db.execute(query).scalar()
    return result or 0

def get_latest_click(db: Session):
    # Fixed: Wrapped with text() and added .fetchone()
    query = text("""SELECT * FROM "baubau_table" ORDER BY id DESC LIMIT 1;""")
    result = db.execute(query)
    return result.fetchone()

def get_clicks_in_last_n_minutes(db: Session, minutes: int = 60) -> int:
    """Returns the total number of clicks registered in the last N minutes."""
    query = text("""
        SELECT COUNT(*) 
        FROM "baubau_table" 
        WHERE timestamp >= NOW() - (:minutes || ' minutes')::INTERVAL;
    """)
    result = db.execute(query, {"minutes": minutes}).scalar()
    return result or 0