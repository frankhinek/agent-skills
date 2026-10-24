def reserve(driver, key):
    return driver.put_if_absent(key)
