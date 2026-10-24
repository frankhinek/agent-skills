from export_transport_driver import Client


def submit(request_id, payload):
    client = Client.from_deployment()
    client.put(request_id, payload)
    return {"durable": True, "id": request_id}
