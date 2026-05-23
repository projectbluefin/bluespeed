#!/usr/bin/env python3
"""kvnc-proxy: bridges KubeVirt WebSocket VNC to raw TCP RFB for guacd."""
import asyncio
import ssl
import os

import websockets

NAMESPACE = os.environ.get("VM_NAMESPACE", "default")
VM_NAME   = os.environ["VM_NAME"]
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "5900"))

with open("/var/run/secrets/kubernetes.io/serviceaccount/token") as f:
    TOKEN = f.read().strip()

CA_CERT  = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
API_HOST = os.environ["KUBERNETES_SERVICE_HOST"]
API_PORT = os.environ.get("KUBERNETES_SERVICE_PORT_HTTPS", "443")

VNC_URL = (
    f"wss://{API_HOST}:{API_PORT}/apis/subresources.kubevirt.io/v1"
    f"/namespaces/{NAMESPACE}/virtualmachineinstances/{VM_NAME}/vnc"
)


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    ssl_ctx = ssl.create_default_context(cafile=CA_CERT)
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        async with websockets.connect(
            VNC_URL,
            additional_headers=headers,
            ssl=ssl_ctx,
            subprotocols=["binary"],
            max_size=None,
            ping_interval=None,
        ) as ws:
            async def tcp_to_ws():
                while True:
                    data = await reader.read(65536)
                    if not data:
                        break
                    await ws.send(data)

            async def ws_to_tcp():
                async for msg in ws:
                    writer.write(msg if isinstance(msg, bytes) else msg.encode())
                    await writer.drain()

            done, pending = await asyncio.wait(
                [asyncio.create_task(tcp_to_ws()),
                 asyncio.create_task(ws_to_tcp())],
                return_when=asyncio.FIRST_COMPLETED,
            )
            for t in pending:
                t.cancel()
    except Exception as e:
        print(f"[kvnc-proxy] connection error: {e}")
    finally:
        writer.close()


async def main():
    server = await asyncio.start_server(handle_client, "0.0.0.0", LISTEN_PORT)
    print(f"[kvnc-proxy] {VM_NAME} listening :{LISTEN_PORT} -> {VNC_URL}")
    async with server:
        await server.serve_forever()


asyncio.run(main())
