"""表紙から2ファイルを取り込み、結果シートを更新する xlsm を作る。"""

from __future__ import annotations

import struct
import zipfile
from pathlib import Path

from pyopenvba import ExcelFile
from pyopenvba.apps.excel import ExcelApplication

OUT = Path(
    "/Users/junyamada/ws/aipm_v0/Flow/202609/2026-09-25/"
    "AIDPC_アウトプットファイル設計/20260925_コーディング結果_取り込み.xlsm"
)

VBA = r"""Option Explicit

Public Sub ImportPatientList()
    ImportFile PatientsName(), "Excelファイル,*.xlsx;*.xlsm;*.xls", "B12"
End Sub

Public Sub ImportCodingResults()
    ImportFile CodingName(), "CSV,*.csv,Excelファイル,*.xlsx;*.xlsm;*.xls", "B13"
End Sub

Public Sub UpdateResultSheet()
    On Error GoTo Fail
    Application.ScreenUpdating = False

    Dim wsP As Worksheet
    Dim wsC As Worksheet
    Dim wsR As Worksheet
    If Not TrySheet(PatientsName(), wsP) Or Not TrySheet(CodingName(), wsC) Then
        MsgBox "先に患者一覧とコーディング結果を取り込んでください。", vbExclamation
        GoTo Done
    End If
    Set wsR = ThisWorkbook.Worksheets(ResultName())

    Dim thresholdCell As Range
    Set thresholdCell = ThisWorkbook.Worksheets(CoverName()).Range(ThresholdAddress())
    EnsureThresholdList thresholdCell
    Dim threshold As Double
    If Not TryThreshold(thresholdCell.Value, threshold) Then
        MsgBox "表紙の「自信度の閾値」で 0.5～1 の値を選んでください。", vbExclamation
        GoTo Done
    End If
    Dim thrText As String
    thrText = Format$(threshold, "0.0")

    Dim pLast As Long, pCols As Long
    Dim cLast As Long, cCols As Long
    pLast = LastRow(wsP)
    pCols = LastCol(wsP)
    cLast = LastRow(wsC)
    cCols = LastCol(wsC)
    If pLast < 2 Or cLast < 2 Then
        MsgBox "取り込みシートにデータ行がありません。", vbExclamation
        GoTo Done
    End If

    Dim patients As Variant
    Dim coding As Variant
    patients = wsP.Range("A1").Resize(pLast, pCols).Value
    coding = wsC.Range("A1").Resize(cLast, cCols).Value

    Dim pId As Long, pAdm As Long, pDis As Long
    Dim pDept As Long, pWard As Long, pDpc As Long, pScore As Long
    pId = ColOfAny(patients, Array("患者ID", "患者番号"))
    pAdm = ColOfAny(patients, Array("入院日", "入院年月日"))
    pDis = ColOfAny(patients, Array("退院日", "退院年月日"))
    pDept = ColOf(patients, "診療科")
    pWard = ColOf(patients, "病棟")
    pDpc = ColOfAny(patients, Array("DPCコード14桁", "DCPコード14桁", "DPCコード"))
    pScore = ColOf(patients, "点数")
    If pId = 0 Or pAdm = 0 Or pDis = 0 Or pDpc = 0 Or pScore = 0 Then
        MsgBox "患者一覧には「患者ID」「入院日」「退院日」「DPCコード14桁」「点数」が必要です。", vbExclamation
        GoTo Done
    End If

    Dim cId As Long, cAdm As Long, cDpc As Long, cScore As Long, cConf As Long, cDecision As Long
    Dim cIcd As Long, cIcdName As Long
    cId = ColOf(coding, "patient_id")
    cAdm = ColOf(coding, "admission_date")
    cDpc = ColOf(coding, "dpc14")
    cScore = ColOf(coding, "final_total_score")
    cConf = ColOf(coding, "step1_confidence")
    cDecision = ColOf(coding, "final_decision")
    cIcd = ColOf(coding, "step1_icd10")
    cIcdName = ColOf(coding, "step1_icd10_name")
    If cId = 0 Or cAdm = 0 Or cDpc = 0 Or cScore = 0 Or cConf = 0 Then
        MsgBox "コーディング結果に patient_id, admission_date, dpc14, final_total_score, step1_confidence が必要です。", vbExclamation
        GoTo Done
    End If

    Dim out() As Variant
    ReDim out(1 To pLast, 1 To 20)
    Dim n As Long
    n = 0
    Dim r As Long
    Dim i As Long
    For r = 2 To pLast
        Dim idKey As String
        Dim dateKey As String
        idKey = NormId(patients(r, pId))
        dateKey = NormDate(patients(r, pAdm))
        If Len(idKey) = 0 Or Len(dateKey) = 0 Then GoTo NextPatient
        Dim best As Long
        best = BestCodingRow(coding, cId, cAdm, cDpc, cScore, cConf, cDecision, idKey, dateKey)
        If best = 0 Then GoTo NextPatient
        n = n + 1
        out(n, 1) = PatientIdValue(patients(r, pId))
        out(n, 2) = ToDate(patients(r, pAdm))
        out(n, 3) = ToDate(patients(r, pDis))
        out(n, 4) = StayDays(out(n, 2), out(n, 3))
        If pDept > 0 Then out(n, 5) = patients(r, pDept)
        If pWard > 0 Then out(n, 6) = patients(r, pWard)
        out(n, 7) = patients(r, pDpc)
        out(n, 8) = ToNumber(patients(r, pScore))
        If cIcd > 0 Then out(n, 9) = coding(best, cIcd)
        If cIcdName > 0 Then out(n, 10) = coding(best, cIcdName)
        out(n, 11) = coding(best, cDpc)
        out(n, 12) = ToNumber(coding(best, cScore))
        out(n, 13) = ScoreDiff(out(n, 12), out(n, 8))
        out(n, 14) = CodeLabel(out(n, 7), out(n, 11))
        out(n, 15) = EvalLabel(out(n, 14), out(n, 8), out(n, 12))
        Dim topRow As Long
        topRow = TopScoreRow(coding, cId, cAdm, cDpc, cScore, cConf, idKey, dateKey, threshold)
        If topRow > 0 Then
            out(n, 16) = coding(topRow, cDpc)
            out(n, 17) = ToNumber(coding(topRow, cScore))
            out(n, 18) = ScoreDiff(out(n, 17), out(n, 8))
            out(n, 19) = IncreaseLabel(out(n, 17), out(n, 8))
        End If
        out(n, 20) = best
NextPatient:
    Next r

    If wsR.AutoFilterMode Then wsR.AutoFilterMode = False
    wsR.Hyperlinks.Delete
    wsR.Cells.Clear
    wsR.Range("A1").Value = "AIコーディング前"
    wsR.Range("I1").Value = "コーディング結果（最高自信度）"
    wsR.Range("P1").Value = "コーディング結果（閾値" & thrText & "以上）"
    Dim headers As Variant
    headers = Array( _
        "患者ID", "入院日", "退院日", "在院日数", "診療科", "病棟", "DPC", "点数", _
        "ICD10コード", "ICD10名称", "DPC", "点数", "点数差", "コード一致", "評価", _
        "最高点のDPC", "点数", "点数差", "増収候補")
    For i = 0 To UBound(headers)
        wsR.Cells(2, i + 1).Value = headers(i)
    Next i
    If n > 0 Then
        wsR.Range("A3").Resize(n, 20).Value = SliceRows(out, n, 20)
        wsR.Range("A3").Resize(n, 20).Sort _
            Key1:=wsR.Range("B3"), Order1:=xlAscending, _
            Key2:=wsR.Range("A3"), Order2:=xlAscending, _
            Header:=xlNo
        For r = 3 To n + 2
            wsR.Hyperlinks.Add Anchor:=wsR.Cells(r, 1), Address:="", _
                SubAddress:="'" & CodingName() & "'!A" & wsR.Cells(r, 20).Value
        Next r
        wsR.Range("T3").Resize(n, 1).ClearContents
    End If
    FormatResult wsR, n
    wsR.Activate
    MsgBox "結果シートを更新しました（" & n & "件）。", vbInformation
    GoTo Done
Fail:
    MsgBox "結果の更新に失敗しました: " & Err.Description, vbExclamation
Done:
    Application.ScreenUpdating = True
End Sub

Private Sub ImportFile(ByVal sheetName As String, ByVal filterSpec As String, ByVal statusCell As String)
    On Error GoTo Fail
    Dim picked As Variant
    picked = Application.GetOpenFilename(filterSpec, , sheetName & "を選択")
    If VarType(picked) = vbBoolean Then Exit Sub

    Application.ScreenUpdating = False
    Dim isCsv As Boolean
    isCsv = (LCase$(Right$(CStr(picked), 4)) = ".csv")
    Dim data As Variant
    Dim lastR As Long
    Dim lastC As Long
    lastR = 0
    lastC = 0
    If isCsv Then
        data = ReadCsv(CStr(picked))
        If IsArray(data) Then
            lastR = UBound(data, 1)
            lastC = UBound(data, 2)
        End If
    Else
        Dim srcBook As Workbook
        Set srcBook = Workbooks.Open(Filename:=CStr(picked), ReadOnly:=True)
        Dim src As Worksheet
        Set src = srcBook.Worksheets(1)
        lastR = LastRow(src)
        lastC = LastCol(src)
        If lastR >= 1 And lastC >= 1 Then data = src.Range("A1").Resize(lastR, lastC).Value
        srcBook.Close SaveChanges:=False
    End If
    If lastR < 1 Or lastC < 1 Then
        MsgBox "ファイルにセルがありません。", vbExclamation
        GoTo Done
    End If

    Dim dst As Worksheet
    Set dst = SheetOrNew(sheetName)
    If dst.AutoFilterMode Then dst.AutoFilterMode = False
    dst.Cells.Clear
    ' Keep CSV values as text so codes, long evidence and cells starting with "=" or "-" are not converted.
    If isCsv Then dst.Cells.NumberFormat = "@"
    dst.Range("A1").Resize(lastR, lastC).Value = data
    dst.Rows(1).Font.Bold = True
    If sheetName = CodingName() And lastR >= 2 Then
        With dst.Rows("2:" & lastR)
            ' 67.5pt = 90px at 100% display scaling
            .RowHeight = 67.5
            .VerticalAlignment = xlTop
        End With
    End If
    If sheetName = CodingName() Then FreezeHeader dst
    ThisWorkbook.Worksheets(CoverName()).Range(statusCell).Value = (lastR - 1) & "件"
    MsgBox sheetName & "を取り込みました（" & (lastR - 1) & "件）。", vbInformation
    GoTo Done
Fail:
    MsgBox "取り込みに失敗しました: " & Err.Description, vbExclamation
Done:
    Application.ScreenUpdating = True
End Sub

Private Function SheetOrNew(ByVal sheetName As String) As Worksheet
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(sheetName)
    On Error GoTo 0
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        ws.Name = sheetName
    End If
    Set SheetOrNew = ws
End Function

Private Sub FreezeHeader(ByVal ws As Worksheet)
    Dim prev As Object
    Set prev = ActiveSheet
    ws.Activate
    With ActiveWindow
        .FreezePanes = False
        .ScrollRow = 1
        .ScrollColumn = 1
        .SplitColumn = 0
        .SplitRow = 1
        .FreezePanes = True
    End With
    prev.Activate
End Sub

Private Function ReadCsv(ByVal path As String) As Variant
    Dim bytes() As Byte
    bytes = ReadAllBytes(path)
    ReadCsv = ParseCsv(DecodeText(bytes))
End Function

Private Function ReadAllBytes(ByVal path As String) As Byte()
    Dim bytes() As Byte
    On Error GoTo UseOpen
    Dim stream As Object
    Set stream = CreateObject("ADODB.Stream")
    stream.Type = 1
    stream.Open
    stream.LoadFromFile path
    If stream.Size > 0 Then bytes = stream.Read
    stream.Close
    ReadAllBytes = bytes
    Exit Function
UseOpen:
    On Error GoTo 0
    Dim f As Integer
    f = FreeFile
    Open path For Binary Access Read As #f
    If LOF(f) > 0 Then
        ReDim bytes(0 To LOF(f) - 1)
        Get #f, , bytes
    End If
    Close #f
    ReadAllBytes = bytes
End Function

Private Function DecodeText(ByRef bytes() As Byte) As String
    Dim n As Long
    n = 0
    On Error Resume Next
    n = UBound(bytes) + 1
    On Error GoTo 0
    If n = 0 Then
        DecodeText = ""
        Exit Function
    End If
    Dim start As Long
    start = 0
    If n >= 3 Then
        If bytes(0) = &HEF And bytes(1) = &HBB And bytes(2) = &HBF Then start = 3
    End If
    Dim text As String
    If Utf8Decode(bytes, start, n, text) Then
        DecodeText = text
    Else
        DecodeText = StrConv(bytes, vbUnicode)
    End If
End Function

Private Function Utf8Decode(ByRef bytes() As Byte, ByVal start As Long, ByVal n As Long, ByRef text As String) As Boolean
    Dim buf As String
    buf = String$(n, vbNullChar)
    Dim pos As Long
    pos = 0
    Dim i As Long
    i = start
    Dim b As Long
    Dim cp As Long
    Dim extra As Long
    Dim k As Long
    Do While i < n
        b = bytes(i)
        If b < &H80 Then
            cp = b
            extra = 0
        ElseIf (b And &HE0) = &HC0 Then
            cp = b And &H1F
            extra = 1
        ElseIf (b And &HF0) = &HE0 Then
            cp = b And &HF
            extra = 2
        ElseIf (b And &HF8) = &HF0 Then
            cp = b And &H7
            extra = 3
        Else
            Exit Function
        End If
        If i + extra >= n Then Exit Function
        For k = 1 To extra
            If (bytes(i + k) And &HC0) <> &H80 Then Exit Function
            cp = cp * &H40 + (bytes(i + k) And &H3F)
        Next k
        i = i + extra + 1
        If cp >= &H10000 Then
            cp = cp - &H10000
            pos = pos + 1
            Mid$(buf, pos, 1) = ChrW(&HD800& + (cp \ &H400))
            pos = pos + 1
            Mid$(buf, pos, 1) = ChrW(&HDC00& + (cp And &H3FF))
        Else
            pos = pos + 1
            Mid$(buf, pos, 1) = ChrW(cp)
        End If
    Loop
    text = Left$(buf, pos)
    Utf8Decode = True
End Function

Private Function ParseCsv(ByRef text As String) As Variant
    Dim records As New Collection
    Dim fields() As String
    Dim fc As Long
    Dim maxCols As Long
    Dim n As Long
    Dim i As Long
    Dim k As Long
    Dim j As Long
    Dim fieldText As String
    Dim c As String
    n = Len(text)
    i = 1
    fc = 0
    maxCols = 0
    ReDim fields(1 To 16)
    Do While i <= n
        If Mid$(text, i, 1) = """" Then
            j = i + 1
            Do
                k = InStr(j, text, """")
                If k = 0 Then
                    fieldText = Mid$(text, i + 1)
                    i = n + 1
                    Exit Do
                End If
                If Mid$(text, k + 1, 1) = """" Then
                    j = k + 2
                Else
                    fieldText = Mid$(text, i + 1, k - i - 1)
                    i = k + 1
                    Exit Do
                End If
            Loop
            fieldText = Replace$(fieldText, """""", """")
        Else
            fieldText = ""
        End If
        k = i
        Do While k <= n
            c = Mid$(text, k, 1)
            If c = "," Or c = vbCr Or c = vbLf Then Exit Do
            k = k + 1
        Loop
        fieldText = fieldText & Mid$(text, i, k - i)
        i = k

        fc = fc + 1
        If fc > UBound(fields) Then ReDim Preserve fields(1 To fc * 2)
        fields(fc) = fieldText

        If i > n Then Exit Do
        c = Mid$(text, i, 1)
        If c = "," Then
            i = i + 1
            If i > n Then
                fc = fc + 1
                If fc > UBound(fields) Then ReDim Preserve fields(1 To fc * 2)
                fields(fc) = ""
            End If
        Else
            If c = vbCr And Mid$(text, i + 1, 1) = vbLf Then i = i + 2 Else i = i + 1
            AddCsvRow records, fields, fc, maxCols
            fc = 0
        End If
    Loop
    If fc > 0 Then AddCsvRow records, fields, fc, maxCols

    If records.Count = 0 Or maxCols = 0 Then
        ParseCsv = Empty
        Exit Function
    End If
    Dim data() As Variant
    ReDim data(1 To records.Count, 1 To maxCols)
    Dim r As Long
    Dim record As Variant
    For r = 1 To records.Count
        record = records(r)
        For k = 1 To UBound(record)
            data(r, k) = record(k)
        Next k
    Next r
    ParseCsv = data
End Function

Private Sub AddCsvRow(ByVal records As Collection, ByRef fields() As String, ByVal fc As Long, ByRef maxCols As Long)
    If fc = 1 And Len(fields(1)) = 0 Then Exit Sub
    Dim record() As String
    ReDim record(1 To fc)
    Dim k As Long
    For k = 1 To fc
        record(k) = fields(k)
    Next k
    records.Add record
    If fc > maxCols Then maxCols = fc
End Sub

Private Function TrySheet(ByVal sheetName As String, ByRef ws As Worksheet) As Boolean
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(sheetName)
    TrySheet = Not ws Is Nothing
    On Error GoTo 0
End Function

Private Function LastRow(ByVal ws As Worksheet) As Long
    LastRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row
    If LastRow = 1 And Len(Trim$(AsText(ws.Cells(1, 1).Value))) = 0 Then LastRow = 0
End Function

Private Function LastCol(ByVal ws As Worksheet) As Long
    LastCol = ws.Cells(1, ws.Columns.Count).End(xlToLeft).Column
    If LastCol = 1 And Len(Trim$(AsText(ws.Cells(1, 1).Value))) = 0 Then LastCol = 0
End Function

Private Function AsText(ByVal v As Variant) As String
    If IsEmpty(v) Or IsNull(v) Then
        AsText = ""
    Else
        AsText = CStr(v)
    End If
End Function

Private Function ColOf(ByVal data As Variant, ByVal name As String) As Long
    Dim c As Long
    For c = 1 To UBound(data, 2)
        If Trim$(AsText(data(1, c))) = name Then
            ColOf = c
            Exit Function
        End If
    Next c
    ColOf = 0
End Function

Private Function ColOfAny(ByVal data As Variant, ByVal names As Variant) As Long
    Dim i As Long
    For i = LBound(names) To UBound(names)
        ColOfAny = ColOf(data, CStr(names(i)))
        If ColOfAny > 0 Then Exit Function
    Next i
    ColOfAny = 0
End Function

Private Function BestCodingRow( _
    ByVal data As Variant, ByVal idCol As Long, ByVal dateCol As Long, _
    ByVal dpcCol As Long, ByVal scoreCol As Long, ByVal confCol As Long, ByVal decisionCol As Long, _
    ByVal idKey As String, ByVal dateKey As String) As Long
    Dim r As Long
    Dim best As Long
    Dim bestConf As Double
    Dim have As Boolean
    best = 0
    have = False
    For r = 2 To UBound(data, 1)
        If NormId(data(r, idCol)) <> idKey Then GoTo NextCoding
        If NormDate(data(r, dateCol)) <> dateKey Then GoTo NextCoding
        If Len(NormCode(data(r, dpcCol))) = 0 Then GoTo NextCoding
        Dim conf As Double
        conf = ConfidenceOf(data(r, confCol))
        If Not have Then
            best = r
            bestConf = conf
            have = True
        ElseIf conf > bestConf + 0.0000001 Then
            best = r
            bestConf = conf
        ElseIf Abs(conf - bestConf) <= 0.0000001 Then
            If BetterCandidate(data, r, best, scoreCol, decisionCol) Then best = r
        End If
NextCoding:
    Next r
    BestCodingRow = best
End Function

Private Function BetterCandidate( _
    ByVal data As Variant, ByVal challenger As Long, ByVal incumbent As Long, _
    ByVal scoreCol As Long, ByVal decisionCol As Long) As Boolean
    Dim challengerSelected As Boolean
    Dim incumbentSelected As Boolean
    challengerSelected = False
    incumbentSelected = False
    If decisionCol > 0 Then
        challengerSelected = (LCase$(Trim$(AsText(data(challenger, decisionCol)))) = "selected")
        incumbentSelected = (LCase$(Trim$(AsText(data(incumbent, decisionCol)))) = "selected")
        If challengerSelected And Not incumbentSelected Then
            BetterCandidate = True
            Exit Function
        End If
        If incumbentSelected And Not challengerSelected Then
            BetterCandidate = False
            Exit Function
        End If
    End If
    BetterCandidate = ConfidenceOf(data(challenger, scoreCol)) > ConfidenceOf(data(incumbent, scoreCol))
End Function

Private Function TopScoreRow( _
    ByVal data As Variant, ByVal idCol As Long, ByVal dateCol As Long, _
    ByVal dpcCol As Long, ByVal scoreCol As Long, ByVal confCol As Long, _
    ByVal idKey As String, ByVal dateKey As String, ByVal threshold As Double) As Long
    Dim r As Long
    Dim best As Long
    Dim bestScore As Double
    Dim bestConf As Double
    best = 0
    For r = 2 To UBound(data, 1)
        If NormId(data(r, idCol)) <> idKey Then GoTo NextRow
        If NormDate(data(r, dateCol)) <> dateKey Then GoTo NextRow
        If Len(NormCode(data(r, dpcCol))) = 0 Then GoTo NextRow
        Dim conf As Double
        conf = ConfidenceOf(data(r, confCol))
        If conf < threshold - 0.0000001 Then GoTo NextRow
        Dim score As Double
        score = ConfidenceOf(data(r, scoreCol))
        If score < 0 Then GoTo NextRow
        If best = 0 Or score > bestScore Or (score = bestScore And conf > bestConf + 0.0000001) Then
            best = r
            bestScore = score
            bestConf = conf
        End If
NextRow:
    Next r
    TopScoreRow = best
End Function

Private Function IncreaseLabel(ByVal aiScore As Variant, ByVal listScore As Variant) As String
    If Not IsNumeric(aiScore) Or Not IsNumeric(listScore) _
        Or Len(Trim$(AsText(aiScore))) = 0 Or Len(Trim$(AsText(listScore))) = 0 Then
        IncreaseLabel = ""
    ElseIf CDbl(aiScore) > CDbl(listScore) Then
        IncreaseLabel = "増収候補"
    Else
        IncreaseLabel = "対象外"
    End If
End Function

Private Function TryThreshold(ByVal v As Variant, ByRef threshold As Double) As Boolean
    TryThreshold = False
    If Len(Trim$(AsText(v))) = 0 Or Not IsNumeric(v) Then Exit Function
    threshold = CDbl(v)
    TryThreshold = (threshold >= 0.5 - 0.0000001 And threshold <= 1 + 0.0000001)
End Function

Private Sub EnsureThresholdList(ByVal cell As Range)
    Dim kind As Long
    kind = -1
    On Error Resume Next
    kind = cell.Validation.Type
    On Error GoTo 0
    If kind = xlValidateList Then Exit Sub
    cell.Validation.Delete
    cell.Validation.Add Type:=xlValidateList, AlertStyle:=xlValidAlertStop, _
        Formula1:="0.5,0.6,0.7,0.8,0.9,1"
    cell.Validation.InCellDropdown = True
End Sub

Private Function ConfidenceOf(ByVal v As Variant) As Double
    If IsNumeric(v) And Len(Trim$(AsText(v))) > 0 Then
        ConfidenceOf = CDbl(v)
    Else
        ConfidenceOf = -1
    End If
End Function

Private Function PatientIdValue(ByVal v As Variant) As Variant
    If IsNumeric(v) And Len(Trim$(AsText(v))) > 0 Then
        PatientIdValue = CLng(v)
    Else
        PatientIdValue = Trim$(AsText(v))
    End If
End Function

Private Function StayDays(ByVal adm As Variant, ByVal dis As Variant) As Variant
    If IsDate(adm) And IsDate(dis) Then
        StayDays = DateDiff("d", CDate(adm), CDate(dis)) + 1
    Else
        StayDays = ""
    End If
End Function

Private Function NormCode(ByVal v As Variant) As String
    Dim s As String
    s = LCase$(Trim$(AsText(v)))
    s = Replace$(s, " ", "")
    s = Replace$(s, "　", "")
    NormCode = s
End Function

Private Function CodeLabel(ByVal listCode As Variant, ByVal aiCode As Variant) As String
    Dim a As String
    Dim b As String
    a = NormCode(listCode)
    b = NormCode(aiCode)
    If Len(a) = 0 Or Len(b) = 0 Then
        CodeLabel = "6桁不一致"
    ElseIf a = b Then
        CodeLabel = "完全一致"
    ElseIf Left$(a, 6) = Left$(b, 6) Then
        CodeLabel = "7桁以降不一致"
    Else
        CodeLabel = "6桁不一致"
    End If
End Function

Private Function EvalLabel(ByVal codeResult As String, ByVal listScore As Variant, ByVal aiScore As Variant) As String
    If codeResult = "完全一致" Then
        EvalLabel = "一致"
        Exit Function
    End If
    If codeResult = "7桁以降不一致" Then
        EvalLabel = "要確認"
        Exit Function
    End If
    If Not IsNumeric(listScore) Or Not IsNumeric(aiScore) _
        Or Len(Trim$(AsText(listScore))) = 0 Or Len(Trim$(AsText(aiScore))) = 0 Then
        EvalLabel = "要確認"
        Exit Function
    End If
    If CDbl(aiScore) > CDbl(listScore) Then
        EvalLabel = "増収候補"
    ElseIf CDbl(aiScore) < CDbl(listScore) Then
        EvalLabel = "アップコーディング候補"
    Else
        EvalLabel = "一致"
    End If
End Function

Private Function ScoreDiff(ByVal aiScore As Variant, ByVal listScore As Variant) As Variant
    If IsNumeric(aiScore) And IsNumeric(listScore) Then
        If Len(Trim$(AsText(aiScore))) > 0 And Len(Trim$(AsText(listScore))) > 0 Then
            ScoreDiff = CDbl(aiScore) - CDbl(listScore)
            Exit Function
        End If
    End If
    ScoreDiff = ""
End Function

Private Function NormId(ByVal v As Variant) As String
    If IsNumeric(v) And Len(Trim$(AsText(v))) > 0 Then
        NormId = CStr(CLng(v))
    Else
        NormId = Trim$(AsText(v))
    End If
End Function

Private Function NormDate(ByVal v As Variant) As String
    If IsDate(v) Then
        NormDate = Format$(CDate(v), "yyyy-mm-dd")
    Else
        Dim s As String
        s = Replace$(Trim$(AsText(v)), "/", "-")
        If Len(s) >= 10 Then
            NormDate = Left$(s, 10)
        Else
            NormDate = s
        End If
    End If
End Function

Private Function ToDate(ByVal v As Variant) As Variant
    On Error GoTo Keep
    If IsDate(v) Then
        ToDate = CDate(v)
        Exit Function
    End If
    Dim s As String
    s = Replace$(Trim$(AsText(v)), "/", "-")
    If Len(s) >= 10 Then
        ToDate = DateSerial(CInt(Left$(s, 4)), CInt(Mid$(s, 6, 2)), CInt(Mid$(s, 9, 2)))
        Exit Function
    End If
Keep:
    ToDate = v
End Function

Private Function ToNumber(ByVal v As Variant) As Variant
    If Len(Trim$(AsText(v))) = 0 Or Not IsNumeric(v) Then
        ToNumber = v
    ElseIf InStr(AsText(v), ".") > 0 Then
        ToNumber = CDbl(v)
    Else
        ToNumber = CLng(v)
    End If
End Function

Private Function SliceRows(ByRef data As Variant, ByVal n As Long, ByVal cols As Long) As Variant
    Dim block() As Variant
    ReDim block(1 To n, 1 To cols)
    Dim r As Long
    Dim c As Long
    For r = 1 To n
        For c = 1 To cols
            block(r, c) = data(r, c)
        Next c
    Next r
    SliceRows = block
End Function

Private Sub FormatResult(ByVal ws As Worksheet, ByVal n As Long)
    ws.Activate
    Dim last As Long
    last = n + 2
    With ws.Range("A1:S2")
        .Font.Bold = True
        .Font.Color = vbWhite
        .Font.Name = "游ゴシック"
        .VerticalAlignment = xlCenter
        .WrapText = True
        .Borders.LineStyle = xlContinuous
        .Borders.Color = vbWhite
    End With
    ws.Range("A1:H1").HorizontalAlignment = xlCenterAcrossSelection
    ws.Range("I1:O1").HorizontalAlignment = xlCenterAcrossSelection
    ws.Range("P1:S1").HorizontalAlignment = xlCenterAcrossSelection
    ws.Range("A1:S1").Borders(xlInsideVertical).LineStyle = xlNone
    Dim edge As Variant
    For Each edge In Array("H1", "O1")
        ws.Range(edge).Borders(xlEdgeRight).LineStyle = xlContinuous
        ws.Range(edge).Borders(xlEdgeRight).Color = vbWhite
    Next edge
    ws.Range("A2:S2").HorizontalAlignment = xlCenter
    ws.Rows(1).RowHeight = 24
    ws.Rows(2).RowHeight = 30
    ws.Range("A1:H2").Interior.Color = RGB(31, 78, 121)
    ws.Range("I1:S2").Interior.Color = RGB(56, 87, 35)
    ws.Columns("A").ColumnWidth = 12
    ws.Columns("B:C").ColumnWidth = 14
    ws.Columns("D").ColumnWidth = 10
    ws.Columns("E").ColumnWidth = 16
    ws.Columns("F").ColumnWidth = 12
    ws.Columns("G").ColumnWidth = 18
    ws.Columns("H").ColumnWidth = 12
    ws.Columns("I").ColumnWidth = 14
    ws.Columns("J").ColumnWidth = 36
    ws.Columns("K").ColumnWidth = 18
    ws.Columns("L").ColumnWidth = 12
    ws.Columns("M").ColumnWidth = 12
    ws.Columns("N").ColumnWidth = 16
    ws.Columns("O").ColumnWidth = 24
    ws.Columns("P").ColumnWidth = 18
    ws.Columns("Q").ColumnWidth = 12
    ws.Columns("R").ColumnWidth = 12
    ws.Columns("S").ColumnWidth = 12
    If n > 0 Then
        ws.Range("A3:S" & last).Font.Name = "游ゴシック"
        ws.Range("B3:C" & last).NumberFormat = "yyyy-mm-dd"
        ws.Range("D3:D" & last).NumberFormat = "0"
        ws.Range("H3:H" & last).NumberFormat = "#,##0"
        ws.Range("L3:M" & last).NumberFormat = "#,##0"
        ws.Range("Q3:R" & last).NumberFormat = "#,##0"
        ws.Rows("3:" & last).VerticalAlignment = xlCenter
    End If
    ws.Range("A2:S" & last).AutoFilter
    With ActiveWindow
        .FreezePanes = False
        .ScrollRow = 1
        .ScrollColumn = 1
        .SplitColumn = 0
        .SplitRow = 2
        .FreezePanes = True
        .ScrollRow = 3
        .ScrollColumn = 1
    End With
    ws.Range("A3").Select
End Sub

Private Function CoverName() As String
    CoverName = "表紙"
End Function

Private Function ThresholdAddress() As String
    ThresholdAddress = "B15"
End Function

Private Function ResultName() As String
    ResultName = "結果"
End Function

Private Function PatientsName() As String
    PatientsName = "患者一覧"
End Function

Private Function CodingName() As String
    CodingName = "コーディング結果"
End Function
"""


def patch_code_page(raw: bytes, new_cp: int = 932) -> bytes:
    sig = b"\x03\x00\x02\x00\x00\x00"
    index = raw.find(sig)
    if index < 0:
        raise SystemExit("PROJECTCODEPAGE record not found")
    current = struct.unpack_from("<H", raw, index + 6)[0]
    if current not in (1252, 932):
        raise SystemExit(f"unexpected code page {current}")
    buf = bytearray(raw)
    struct.pack_into("<H", buf, index + 6, new_cp)
    return bytes(buf)


def build_shell() -> None:
    app = ExcelApplication()
    book = app.add_workbook()
    cover = app.sheet(1)
    cover.sheet.vba_set("Name", "表紙")
    added = book.vba_get("Sheets").Add()
    added.vba_set("Name", "結果")
    # Add puts the new sheet first. Move 表紙 back to the front by recreating order:
    # Sheets.Add(Before) defaults to before active. Move 結果 after 表紙.
    cover_sheet = None
    result_sheet = None
    for view in app.sheets():
        if view.name == "表紙":
            cover_sheet = view
        elif view.name == "結果":
            result_sheet = view
    assert cover_sheet is not None and result_sheet is not None
    result_sheet.sheet.Move(After=cover_sheet.sheet)

    lines = [
        (1, "コーディング結果をユーザー向けに整える"),
        (3, "手順"),
        (4, "1. 「患者一覧を取り込む」で、患者一覧のExcelを指定する"),
        (5, "2. 「コーディング結果を取り込む」で、コーディング結果のCSVを指定する"),
        (6, "3. 「結果シートを更新」で、取り込んだ2シートから結果シートを書き換える"),
        (8, "結果は、患者IDと入院日が一致した行です。AI側は自信度が最も高いDPC14桁を使い、一覧のDPCと点数と比べます。"),
        (9, "あわせて、自信度が下の閾値以上の候補のうち点数が最も高いDPCとも比べ、増収候補かどうかを出します。"),
        (11, "取込状況"),
        (12, "患者一覧"),
        (13, "コーディング結果"),
        (15, "自信度の閾値（0.5〜1。右のセルで選ぶ）"),
    ]
    for row, text in lines:
        cover_sheet.set_value(f"A{row}", text)
    cover_sheet.set_value("B12", "未取込")
    cover_sheet.set_value("B13", "未取込")
    # The dropdown on B15 is added by EnsureThresholdList the first time 結果シートを更新 runs.
    cover_sheet.set_value("B15", 0.5)
    result_sheet.set_value("A1", "表紙の「結果シートを更新」を実行すると、ここに書き込まれます。")

    cover_sheet.sheet.vba_get("Columns", ["A"]).vba_set("ColumnWidth", 96)
    cover_sheet.sheet.vba_get("Columns", ["B"]).vba_set("ColumnWidth", 16)

    buttons = [
        ("btnPatients", 230, "患者一覧を取り込む", "ImportPatientList"),
        ("btnCoding", 278, "コーディング結果を取り込む", "ImportCodingResults"),
        ("btnUpdate", 326, "結果シートを更新", "UpdateResultSheet"),
    ]
    for name, top, text, macro in buttons:
        cover_sheet.add_button(
            name=name, left=24, top=top, width=240, height=36, text=text, macro=macro
        )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    app.save(OUT)


def inject_vba() -> None:
    source = VBA.replace("\n", "\r\n")
    with ExcelFile(OUT) as wb:
        project = wb.vba_project()
        project.code_page = 932
        project.dir_raw = patch_code_page(project.dir_raw, 932)
        project.dir_references_dirty = True
        wb.set_module("Module1", source)
        wb.save()


def verify() -> None:
    with ExcelFile(OUT) as wb:
        project = wb.vba_project()
        text = project.get_module("Module1").source
        assert project.code_page == 932, project.code_page
        assert "患者一覧" in text
        assert "ImportPatientList" in text
        assert "UpdateResultSheet" in text
        assert "コード一致" in text
        assert "アップコーディング" in text
        assert "増収候補" in text
    with zipfile.ZipFile(OUT) as zf:
        xml = "\n".join(
            zf.read(name).decode("utf-8", errors="replace")
            for name in zf.namelist()
            if name.endswith(".xml") or name.endswith(".vml")
        )
    for macro in ("ImportPatientList", "ImportCodingResults", "UpdateResultSheet"):
        if macro not in xml:
            raise SystemExit(f"button macro missing: {macro}")
    print(OUT)
    print("code_page", 932)
    print("buttons", "ok")


if __name__ == "__main__":
    build_shell()
    inject_vba()
    verify()
