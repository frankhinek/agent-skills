from .reservations import reserve


def post(driver, key, payload):
    with driver.transaction():
        if reserve(driver, key):
            driver.append(key, payload)
        return driver.lookup(key)
