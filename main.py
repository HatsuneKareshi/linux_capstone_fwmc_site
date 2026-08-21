from db import get_db
from pydantic import BaseModel
import uvicorn
import requests
import os
import time
import sys
from fastapi import FastAPI, Request, Response, Header, HTTPException, Depends
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from typing import Optional, Any
from db import *

class APIResponse(BaseModel):
    bau_cnt: int
    is_mococo: Optional[bool] = None
    bau_within_last_15m: int
    bau_within_last_1h: int


app = FastAPI()

from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/", response_class=FileResponse)
async def serve_index():
    return "index.html"

@app.get("/api/bau-req")
async def api_get_baubau(which: str, db: Session = Depends(get_db)): # gets called on click of either Fuwawa or Mococo. 
    if(which == "mococo"): 
        is_mococo = True
    else:
        is_mococo = False
    click_row = record_click(db, is_mocochan=is_mococo)
    cnt_last_15m = get_clicks_in_last_n_minutes(db, 15)
    cnt_last_1h = get_clicks_in_last_n_minutes(db, 60)
    
    return APIResponse(
        bau_cnt=click_row[0],
        is_mococo=click_row[2],
        bau_within_last_15m=cnt_last_15m,
        bau_within_last_1h=cnt_last_1h,
    )

@app.get("/api/bau-count")
async def api_init_bau_count(db: Session = Depends(get_db)): # is called to collect total tally, though subject to change.
    # no fw or mc check here. 
    bau_count_int = get_total_clicks(db)
    cnt_last_15m = get_clicks_in_last_n_minutes(db, 15)
    cnt_last_1h = get_clicks_in_last_n_minutes(db, 60)
    return APIResponse(
        bau_cnt=bau_count_int,
        bau_within_last_15m=cnt_last_15m,
        bau_within_last_1h=cnt_last_1h,
    ) # is_mococo is None 
    

@app.get("/api/ping")
async def ping(db: Session = Depends(get_db)):
    latest_bau_record = get_latest_click(db)
    cnt_last_15m = get_clicks_in_last_n_minutes(db, 15)
    cnt_last_1h = get_clicks_in_last_n_minutes(db, 60)
    return APIResponse(
        bau_cnt=latest_bau_record[0],
        is_mococo=latest_bau_record[2],
        bau_within_last_15m=cnt_last_15m,
        bau_within_last_1h=cnt_last_1h,
    )

print(0 / 0)

uvicorn.run(app, host="127.0.0.1", port=8000) # log_level="warning"