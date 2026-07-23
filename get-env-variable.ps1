$item = $args[0]
return Select-String -path .\.env -pattern "${item}" -raw "\${item}:(.*)\n/\1/"
