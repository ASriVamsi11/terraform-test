from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def root():
    return {"message" : "Good Morning!"}

@app.get("/health")
def health():
    return {"status": "OK"}