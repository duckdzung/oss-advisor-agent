import chainlit as cl

from agent import build_agent

WELCOME = """### OSS Advisor

Tôi giúp bạn đánh giá thư viện open-source trước khi adopt.

**Bạn có thể hỏi:**
- *"Express 4.18.2 có an toàn không?"*
- *"So sánh các thư viện HTTP client tốt nhất cho Python"*
- *"Audit file pom.xml của tôi tại /path/to/pom.xml"*
- *"HikariCP vs c3p0 cho Java connection pooling?"*

**Profiles:** mặc định `balanced` — gõ `--security-first` hoặc `--adoption-first` để thay đổi trọng số.
"""


@cl.on_chat_start
async def on_chat_start():
    try:
        agent = build_agent()
        cl.user_session.set("agent", agent)
    except ValueError as exc:
        await cl.Message(content=f"Configuration error: {exc}").send()
        return

    await cl.Message(content=WELCOME).send()


@cl.on_message
async def on_message(message: cl.Message):
    agent = cl.user_session.get("agent")
    if agent is None:
        await cl.Message(content="Agent not initialized. Please refresh the page.").send()
        return

    # Handle uploaded manifest files — inject path into message content
    content = message.content
    for element in message.elements:
        if hasattr(element, "path") and element.path:
            name = getattr(element, "name", "file")
            content += f"\n[Uploaded file: {element.path} (name: {name})]"

    answer_msg = cl.Message(content="")
    tool_steps: dict[str, cl.Step] = {}

    try:
        async for event in agent.astream_events(
            {"messages": [{"role": "user", "content": content}]},
            version="v2",
        ):
            kind = event["event"]
            run_id = event.get("run_id", "")

            if kind == "on_tool_start":
                tool_name = event.get("name", "tool")
                step = cl.Step(name=tool_name, type="tool")
                await step.__aenter__()
                step.input = str(event.get("data", {}).get("input", ""))
                tool_steps[run_id] = step

            elif kind == "on_tool_end":
                step = tool_steps.pop(run_id, None)
                if step:
                    output = event.get("data", {}).get("output", "")
                    step.output = str(output)[:800]
                    await step.__aexit__(None, None, None)

            elif kind == "on_chat_model_stream":
                chunk = event["data"].get("chunk")
                if chunk and hasattr(chunk, "content") and chunk.content:
                    await answer_msg.stream_token(chunk.content)

    except Exception as exc:
        await answer_msg.stream_token(f"\n\nError: {exc}")
    finally:
        # Close any steps that didn't receive on_tool_end
        for step in tool_steps.values():
            await step.__aexit__(None, None, None)

    await answer_msg.send()
