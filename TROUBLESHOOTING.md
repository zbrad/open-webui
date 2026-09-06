# Open WebUI Troubleshooting Guide

## Understanding the Open WebUI Architecture

Open WebUI connects to model servers through the OpenAI-compatible API
mechanism — this covers llama.cpp, LMStudio, vLLM, plain OpenAI, Azure
OpenAI, and any other server that speaks the OpenAI chat/completions
protocol. Connections are configured under **Admin Settings → Connections**
(or via `OPENAI_API_BASE_URL`/`OPENAI_API_KEY` at launch — see
[`deploy/local/setup.sh`](deploy/local/setup.sh)), not hardcoded to a single
backend.

## Open WebUI: Server Connection Error

If you're experiencing connection issues, it's often due to the WebUI
docker container not being able to reach your model server at 127.0.0.1
(host.docker.internal) inside the container. Use the `--network=host` flag
in your docker command to resolve this. Note that the port changes from
3000 to 8080, resulting in the link: `http://localhost:8080`.

**Example Docker Command**:

```bash
docker run -d --network=host -v open-webui:/app/backend/data -e OPENAI_API_BASE_URL=http://127.0.0.1:8080/v1 --name open-webui --restart always ghcr.io/open-webui/open-webui:main
```

### Error on Slow Responses

Open WebUI has a default timeout of 5 minutes for the model server to
finish generating a response. If needed, this can be adjusted via the
environment variable `AIOHTTP_CLIENT_TIMEOUT`, which sets the timeout in
seconds.

### General Connection Errors

**Troubleshooting Steps**:

1. **Verify the connection's API base URL**:
   - Under **Admin Settings → Connections**, confirm the API base URL
     points at your model server (e.g. `http://192.168.1.1:8080/v1` for a
     llama.cpp server on a different host).
   - Confirm the server is actually reachable from wherever Open WebUI is
     running (container vs. host networking matters — see above).

By following these troubleshooting steps, connection issues should be
effectively resolved. For further assistance or queries, feel free to
reach out to us on our community Discord.
