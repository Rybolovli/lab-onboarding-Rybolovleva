def get_balance(user_id):
    return 100


def update_balance(user_id, new_balance):
    pass


def process_transaction(user_id, amount, db_connection):
    status = "pending"

    if amount > 0:
        status = "approved"
        balance = get_balance(user_id)
        new_balance = balance - amount
        update_balance(user_id, new_balance)

    log_entry = "Transaction finished with status: " + status

    with open("audit_log.txt", "w") as file:
        file.write(log_entry)

    return status
