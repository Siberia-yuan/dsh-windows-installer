' Poll the dsh web port until ready, then open the browser.
Set http = CreateObject("MSXML2.ServerXMLHTTP")
Set shell = CreateObject("WScript.Shell")
For i = 1 To 90
  On Error Resume Next
  http.Open "GET", "http://127.0.0.1:3080/", False
  http.Send
  If Err.Number = 0 And http.Status = 200 Then
    Exit For
  End If
  Err.Clear
  On Error GoTo 0
  WScript.Sleep 1000
Next
shell.Run "http://127.0.0.1:3080"
