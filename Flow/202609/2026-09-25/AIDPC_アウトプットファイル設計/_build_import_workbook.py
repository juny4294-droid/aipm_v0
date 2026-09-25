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
    pDpc = ColOfAny(patients, Array("DPCコード14桁", "DCPコード14桁"))
    pScore = ColOf(patients, "点数")
    If pId = 0 Or pAdm = 0 Or pDis = 0 Or pDpc = 0 Or pScore = 0 Then
        MsgBox "患者一覧には「患者ID」「入院日」「退院日」「DPCコード14桁」「点数」が必要です。", vbExclamation
        GoTo Done
    End If

    Dim cId As Long, cAdm As Long, cDpc As Long, cScore As Long, cConf As Long, cDecision As Long
    cId = ColOf(coding, "patient_id")
    cAdm = ColOf(coding, "admission_date")
    cDpc = ColOf(coding, "dpc14")
    cScore = ColOf(coding, "final_total_score")
    cConf = ColOf(coding, "step1_confidence")
    cDecision = ColOf(coding, "final_decision")
    If cId = 0 Or cAdm = 0 Or cDpc = 0 Or cScore = 0 Or cConf = 0 Then
        MsgBox "コーディング結果に patient_id, admission_date, dpc14, final_total_score, step1_confidence が必要です。", vbExclamation
        GoTo Done
    End If

    Dim out() As Variant
    ReDim out(1 To pLast, 1 To 13)
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
        out(n, 9) = coding(best, cDpc)
        out(n, 10) = ToNumber(coding(best, cScore))
        out(n, 11) = ScoreDiff(out(n, 10), out(n, 8))
        out(n, 12) = CodeLabel(out(n, 7), out(n, 9))
        out(n, 13) = ScoreLabel(out(n, 8), out(n, 10))
NextPatient:
    Next r

    If wsR.AutoFilterMode Then wsR.AutoFilterMode = False
    wsR.Cells.Clear
    Dim headers As Variant
    headers = Array( _
        "患者ID", "入院日", "退院日", "在院日数", "診療科", "病棟", _
        "現状のDPC", "現状の点数", "AIコーディングのDPC", "AIコーディングの点数", _
        "点数差", "コード一致", "点数一致")
    For i = 0 To UBound(headers)
        wsR.Cells(1, i + 1).Value = headers(i)
    Next i
    If n > 0 Then
        wsR.Range("A2").Resize(n, 13).Value = SliceRows(out, n, 13)
        wsR.Range("A2").Resize(n, 13).Sort _
            Key1:=wsR.Range("B2"), Order1:=xlAscending, _
            Key2:=wsR.Range("A2"), Order2:=xlAscending, _
            Header:=xlNo
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
    Dim srcBook As Workbook
    Dim openedText As Boolean
    openedText = False
    If LCase$(Right$(CStr(picked), 4)) = ".csv" Then
        Workbooks.OpenText Filename:=CStr(picked), Origin:=65001, DataType:=xlDelimited, _
            TextQualifier:=xlDoubleQuote, ConsecutiveDelimiter:=False, _
            Tab:=False, Semicolon:=False, Comma:=True, Space:=False, Other:=False
        Set srcBook = ActiveWorkbook
        openedText = True
    Else
        Set srcBook = Workbooks.Open(Filename:=CStr(picked), ReadOnly:=True)
    End If

    Dim src As Worksheet
    Set src = srcBook.Worksheets(1)
    Dim dst As Worksheet
    Set dst = SheetOrNew(sheetName)
    If dst.AutoFilterMode Then dst.AutoFilterMode = False
    dst.Cells.Clear

    Dim lastR As Long
    Dim lastC As Long
    lastR = LastRow(src)
    lastC = LastCol(src)
    If lastR < 1 Or lastC < 1 Then
        srcBook.Close SaveChanges:=False
        MsgBox "ファイルにセルがありません。", vbExclamation
        GoTo Done
    End If
    dst.Range("A1").Resize(lastR, lastC).Value = src.Range("A1").Resize(lastR, lastC).Value
    srcBook.Close SaveChanges:=False
    dst.Rows(1).Font.Bold = True
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
    If Len(a) > 0 And a = b Then
        CodeLabel = "コード一致"
    Else
        CodeLabel = "コード不一致"
    End If
End Function

Private Function ScoreLabel(ByVal listScore As Variant, ByVal aiScore As Variant) As String
    If Not IsNumeric(listScore) Or Not IsNumeric(aiScore) Then
        ScoreLabel = ""
        Exit Function
    End If
    If Len(Trim$(AsText(listScore))) = 0 Or Len(Trim$(AsText(aiScore))) = 0 Then
        ScoreLabel = ""
        Exit Function
    End If
    If CDbl(listScore) > CDbl(aiScore) Then
        ScoreLabel = "アップコーディング"
    ElseIf CDbl(listScore) < CDbl(aiScore) Then
        ScoreLabel = "増収候補"
    Else
        ScoreLabel = "点数一致"
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
    last = n + 1
    With ws.Rows(1)
        .Font.Bold = True
        .Font.Color = vbWhite
        .Font.Name = "游ゴシック"
        .Interior.Color = RGB(31, 78, 121)
        .HorizontalAlignment = xlCenter
        .VerticalAlignment = xlCenter
        .RowHeight = 36
        .WrapText = True
    End With
    ws.Columns("A").ColumnWidth = 12
    ws.Columns("B:C").ColumnWidth = 14
    ws.Columns("D").ColumnWidth = 12
    ws.Columns("E").ColumnWidth = 16
    ws.Columns("F").ColumnWidth = 12
    ws.Columns("G").ColumnWidth = 20
    ws.Columns("H").ColumnWidth = 14
    ws.Columns("I").ColumnWidth = 22
    ws.Columns("J").ColumnWidth = 22
    ws.Columns("K").ColumnWidth = 12
    ws.Columns("L").ColumnWidth = 14
    ws.Columns("M").ColumnWidth = 18
    If n > 0 Then
        ws.Range("A2:M" & last).Font.Name = "游ゴシック"
        ws.Range("B2:C" & last).NumberFormat = "yyyy-mm-dd"
        ws.Range("D2:D" & last).NumberFormat = "0"
        ws.Range("H2:H" & last).NumberFormat = "#,##0"
        ws.Range("J2:K" & last).NumberFormat = "#,##0"
        ws.Rows("2:" & last).VerticalAlignment = xlCenter
    End If
    ws.Range("A1:M" & last).AutoFilter
    ws.FreezePanes = False
    ws.Range("A2").Select
    ws.FreezePanes = True
    ws.Range("A1").Select
End Sub

Private Function CoverName() As String
    CoverName = "表紙"
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
        (11, "取込状況"),
        (12, "患者一覧"),
        (13, "コーディング結果"),
    ]
    for row, text in lines:
        cover_sheet.set_value(f"A{row}", text)
    cover_sheet.set_value("B12", "未取込")
    cover_sheet.set_value("B13", "未取込")
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
