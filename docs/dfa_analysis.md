# Def-Use цепочки

Переменная: log_entry
Def: строка 2 ("Start processing"), строка 10 (присваивание с status)
Use: строка 13 (file.write(log_entry))

Переменная: status
Def: строка 5 ("approved")
Use: строка 10 (конкатенация), строка 15 (return)

Переменная: balance
Def: строка 6 (get_balance)
Use: строка 7

Переменная: new_balance
Def: строка 7
Use: строка 8 (update_balance)

Переменная: file
Def: строка 12 (open)
Use: строка 13 (file.write)
