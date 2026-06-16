import uvicorn
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from chainlit.utils import mount_chainlit
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="OSS Advisor Agent")


@app.get("/health")
async def health():
    return JSONResponse({"status": "ok"})


# Mount the Chainlit chat UI at the root path.
# chainlit_app.py contains the @cl.on_message / @cl.on_chat_start handlers.
mount_chainlit(app=app, target="chainlit_app.py", path="/")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
