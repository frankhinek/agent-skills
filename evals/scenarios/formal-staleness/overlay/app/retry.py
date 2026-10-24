from .posting import post


def retry(driver, key, payload):
    return post(driver, key, payload)
