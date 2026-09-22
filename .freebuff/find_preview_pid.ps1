Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $PSItem.CommandLine -like '*preview_server*' } |
  Select-Object -ExpandProperty ProcessId
