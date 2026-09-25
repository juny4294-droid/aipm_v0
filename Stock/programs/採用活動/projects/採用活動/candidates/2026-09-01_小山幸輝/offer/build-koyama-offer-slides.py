#!/usr/bin/env python3
"""小山さん向けオファーレター案スライドを生成する。"""

from __future__ import annotations

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

DIR = Path(__file__).resolve().parent
OUT = DIR / "koyama-offer-letter-draft.pptx"
OUT_JP = DIR / "小山さん向けオファーレター_案.pptx"

# MedUp寄り（過度な装飾は避ける）
NAVY = RGBColor(0x08, 0x15, 0x1A)
TEAL = RGBColor(0x08, 0xD0, 0xD0)
ORANGE = RGBColor(0xF3, 0x98, 0x10)
GRAY = RGBColor(0x55, 0x55, 0x55)
LIGHT = RGBColor(0xF5, 0xF7, 0xF8)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
BLACK = RGBColor(0x1A, 0x1A, 0x1A)


def _blank(prs: Presentation):
    return prs.slides.add_slide(prs.slide_layouts[6])


def _rect(slide, left, top, width, height, fill: RGBColor, line: RGBColor | None = None):
    shape = slide.shapes.add_shape(1, left, top, width, height)
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill
    if line:
        shape.line.color.rgb = line
    else:
        shape.line.fill.background()
    return shape


def _text(slide, left, top, width, height, text: str, *, size=14, bold=False, color=BLACK, align=PP_ALIGN.LEFT):
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.word_wrap = True
    lines = text.split("\n")
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = line
        p.font.size = Pt(size)
        p.font.bold = bold
        p.font.color.rgb = color
        p.alignment = align
        p.space_after = Pt(4)
    return box


def _footer(slide, label: str):
    _text(slide, Inches(0.4), Inches(7.05), Inches(12), Inches(0.3), f"© MedUp inc.  |  DRAFT  |  {label}", size=9, color=GRAY)


def section_slide(prs, title: str, number: str):
    slide = _blank(prs)
    _rect(slide, Inches(0), Inches(0), Inches(13.333), Inches(7.5), NAVY)
    _text(slide, Inches(1), Inches(2.6), Inches(11), Inches(0.6), number, size=20, bold=True, color=TEAL)
    _text(slide, Inches(1), Inches(3.2), Inches(11), Inches(1), title, size=32, bold=True, color=WHITE)
    return slide


def content_slide(prs, title: str, body: str, *, footer=""):
    slide = _blank(prs)
    _rect(slide, Inches(0), Inches(0), Inches(13.333), Inches(0.08), TEAL)
    _text(slide, Inches(0.5), Inches(0.35), Inches(12.3), Inches(0.55), title, size=24, bold=True, color=NAVY)
    _text(slide, Inches(0.5), Inches(1.1), Inches(12.3), Inches(5.6), body, size=15, color=BLACK)
    _footer(slide, footer or title)
    return slide


def two_col_slide(prs, title: str, left_title: str, left_body: str, right_title: str, right_body: str):
    slide = _blank(prs)
    _rect(slide, Inches(0), Inches(0), Inches(13.333), Inches(0.08), TEAL)
    _text(slide, Inches(0.5), Inches(0.3), Inches(12.3), Inches(0.5), title, size=22, bold=True, color=NAVY)

    _rect(slide, Inches(0.5), Inches(1.0), Inches(5.9), Inches(5.5), LIGHT)
    _text(slide, Inches(0.7), Inches(1.15), Inches(5.5), Inches(0.45), left_title, size=16, bold=True, color=NAVY)
    _text(slide, Inches(0.7), Inches(1.7), Inches(5.5), Inches(4.5), left_body, size=13, color=BLACK)

    _rect(slide, Inches(6.9), Inches(1.0), Inches(5.9), Inches(5.5), LIGHT)
    _text(slide, Inches(7.1), Inches(1.15), Inches(5.5), Inches(0.45), right_title, size=16, bold=True, color=NAVY)
    _text(slide, Inches(7.1), Inches(1.7), Inches(5.5), Inches(4.5), right_body, size=13, color=BLACK)

    _footer(slide, title)
    return slide


def build() -> Path:
    prs = Presentation()
    prs.slide_width = Inches(13.333)
    prs.slide_height = Inches(7.5)

    # 1 表紙
    s = _blank(prs)
    _rect(s, Inches(0), Inches(0), Inches(13.333), Inches(7.5), NAVY)
    _rect(s, Inches(0), Inches(6.9), Inches(13.333), Inches(0.6), TEAL)
    _text(s, Inches(1), Inches(2.5), Inches(11), Inches(0.8), "小山さん向け", size=36, bold=True, color=WHITE)
    _text(s, Inches(1), Inches(3.4), Inches(11), Inches(0.7), "オファーレター", size=40, bold=True, color=TEAL)
    _text(s, Inches(1), Inches(4.4), Inches(11), Inches(0.4), "2026.09.01（案）", size=18, color=WHITE)
    _text(s, Inches(1), Inches(7.0), Inches(11), Inches(0.35), "DRAFT — 年収・SO・入社日は未確定", size=12, bold=True, color=NAVY)

    # 2 はじめに
    content_slide(
        prs,
        "はじめに",
        "● メダップは、病院経営を改善し、よりよい地域医療を実現する「SaaS/AIスタートアップ」\n"
        "● 前年同月比売上1.6倍で成長中（月次売上12M as of 2025/12）※最新数字に更新可\n"
        "● 強固なデータ基盤を活かした “SaaSコンパウンド” に加え、病院特化のAIによる業務自動化の立上げに取組中\n"
        "● 日本を代表するトップ病院との戦略的パートナーシップを締結\n\n"
        "● 小山さんにFDEリードとして参画いただき、顧客課題の深掘り〜実装・検証まで届ける\n"
        "  探索チームの立ち上げと、セキュリティを含む部門横断の土台づくりを一緒に進めたい\n"
        "● 条件案: 【要確定】入社日・年収・サインナップ／SO",
    )

    # 3 section
    section_slide(prs, "採用の必要性", "01")

    # 4 Vision
    content_slide(
        prs,
        "メダップの目指す Vision",
        "経営から、病院を変える。病院から、医療を変える。\n\n"
        "当社プロダクトが提供できる価値\n"
        "  ・データ化　・意思決定の高度化　・業務の定型化／効率化\n"
        "→ 病院経営・働き方改革\n"
        "→ ひいては 持続可能で質の高い地域医療 に貢献する",
    )

    # 5 社会課題
    content_slide(
        prs,
        "解決したい社会課題",
        "病院の、「求められる医療機能への転換」・\n"
        "「病院の経営（ヒト／カネの持続性）向上」を実現する\n\n"
        "事業戦略（要約）\n"
        "● Step1: 高度急性期病院の患者の流れの最適化（foro CRM 等）\n"
        "● Step2: 中小病院へのサービス最適化\n"
        "● Step3: AI医療事務サービス立ち上げ（AI DPC 等）\n\n"
        "※ Vision・事例・foro詳細は山田さん版スライドを流用して差し替え可",
    )

    # 6 FDE必要性
    content_slide(
        prs,
        "Product部門における課題とFDE採用の必要性",
        "1. いま起きていること\n"
        "● FS・CS・PSの顧客／業務解像度は急速に向上\n"
        "● 一方、顧客課題を技術で捉え、実装・検証まで届ける探索役（FDE）が不足\n"
        "● 既存SaaS（Dev）・定例データ（DataOps）の体制はあるが、\n"
        "  現場課題 → プロダクト価値 のループが弱い\n"
        "● セキュリティ／Infra は属人化しやすく、中長期の引き継ぎが必要\n\n"
        "2. 結論・打ち手\n"
        "顧客課題に深く入り、技術で解を設計・実装し、効果まで届けるFDEチームを立ち上げる。\n"
        "一人目のリードとして、案件完遂とチームの型づくりを同時に担える人材が必須",
    )

    # 7 狙い
    content_slide(
        prs,
        "FDEチーム立ち上げの狙い",
        "今後、既存SaaSの継続改善に加え、AI・新規探索で病院経営課題への\n"
        "インパクトを広げる。\n\n"
        "そのために、顧客現場に入り込み完遂できるFDEチームを立ち上げ、\n"
        "Product部門の「探索」を再現可能な型にする。",
    )

    # 8 section
    section_slide(prs, "小山さんに参画いただきたい理由", "02")

    # 9 理由
    content_slide(
        prs,
        "小山さんに参画いただきたい理由",
        "小山さんは「現場に入り込む力 × 課題の構造化・合意形成 ×\n"
        "ゼロからの立ち上げ・カオス耐性 × セキュリティ／Infra知見」を\n"
        "兼ね備えており、いま立ち上げ期にあるFDEチームに不可欠な力だと考えています。\n\n"
        "● 価値志向\n"
        "  ・「命に関わる領域」に貢献したい軸が一貫（警察・Sec・医療IT）\n"
        "  ・みんなが困っているところに入り、一緒に解決するのが楽しい\n\n"
        "● 両輪の経験\n"
        "  ・前方: 顧客折衝・合意形成（提案〜PoC〜導入運用）\n"
        "  ・後方: Sec/Infra・運用の型づくり（3省2、ISMS、ルール整備）\n\n"
        "● 推進スタイル\n"
        "  ・手探りから手順・チームを作る　・カオスでもやり切る\n"
        "  ・小さめ組織で裁量を持って動く志向 → メダップと相性が良い",
    )

    # 10 提供できること
    two_col_slide(
        prs,
        "小山さんにメダップが提供できること",
        "FDEチームの立ち上げと完遂の型づくり",
        "● 「顧客課題 → 設計・実装・検証」をチームとして回す\n\n"
        "● CS/PSと同じテーブルで現場に入り込む開発\n\n"
        "● セキュリティを含む部門横断の土台づくり",
        "過去の経験・志向を活かせる状況と役割",
        "● 顧客折衝・構造化・立ち上げの経験をFDEリードとして発揮できる\n\n"
        "● Sec/Infra知見を部門の土台づくりに活かせる\n\n"
        "● 正社員として腰を据え、医療ドメインを習得しながら成果を積める\n\n"
        "● 「現場と経営の間」を埋める役割そのもの",
    )

    # 11 section
    section_slide(prs, "参画案ドラフト", "03")

    # 12 期待する役割
    content_slide(
        prs,
        "期待する役割",
        "AI時代かつメダップがSaaS・AIへの変革中で不確実性が高いなか、\n"
        "FDEチームのコアメンバー／リードとして、探索の完遂と型づくりを主導していただきたい\n\n"
        "● ミッション\n"
        "  ・顧客課題を現場で捉え、技術で解を設計・実装し、効果まで届ける\n"
        "  ・FDEチームの運営・案件PM・型づくり\n"
        "  ・セキュリティ方針のたたき台づくり（部門横断）\n\n"
        "● 役割: Forward Deployed Engineer（FDEリード）\n"
        "  ・主: チーム運営・案件PM、CS/PS連携、構造化・優先度判断、型づくり\n"
        "  ・副: セキュリティ主担当\n"
        "  ・実装: 自らも関与しつつ、黒川・メンバーFDEと補完\n\n"
        "● スケジュール案\n"
        "  ・〜1ヶ月: キャッチアップ・関係者接点・Sec現状把握\n"
        "  ・〜3ヶ月: 1案件で完遂の型、運営ルール・Sec基準のたたき台\n"
        "  ・〜1年: 年間2〜3件完遂、チーム自律運営、Sec標準化",
    )

    # 13 section offer
    section_slide(prs, "オファー内容", "03")

    # 14 オファー概要
    s = _blank(prs)
    _rect(s, Inches(0), Inches(0), Inches(13.333), Inches(0.08), TEAL)
    _text(s, Inches(0.5), Inches(0.35), Inches(12), Inches(0.5), "オファー概要", size=24, bold=True, color=NAVY)
    _rect(s, Inches(1.5), Inches(2.2), Inches(10.3), Inches(2.6), LIGHT)
    _text(
        s,
        Inches(1.8),
        Inches(2.5),
        Inches(9.7),
        Inches(2.2),
        "年俸 【要確定】万円\n"
        "（面接メモ: 現900／希望900／最低850）\n\n"
        "+ SO 【要確定】  /  サインナップ 【要確定】\n\n"
        "• Grade 【要確定】",
        size=20,
        bold=True,
        color=NAVY,
        align=PP_ALIGN.CENTER,
    )
    _footer(s, "オファー概要")

    # 15 組織
    content_slide(
        prs,
        "組織図案（Product周辺）",
        "Product部門\n"
        "├── FDE（探索） … 小山（リード）／黒川／メンバー\n"
        "├── Dev（継続） … 廣／新保 ほか\n"
        "├── DataOps（定例） … 藤原ほか\n"
        "├── 横断 Sec/AI/Infra … 小山（Sec）ほか\n"
        "└── PdM・デザイン … 山田 ほか\n\n"
        "管掌範囲\n"
        "● FDEチームの運営・案件推進・型づくり\n"
        "● CS/PSと連携した顧客課題の深掘り〜実装・検証\n"
        "● セキュリティ方針・レビュー\n\n"
        "※ 全社組織図は山田さん版を流用し、Product配下にFDEを追記してもよい",
    )

    # 16 詳細
    content_slide(
        prs,
        "オファー詳細",
        "【入社ポジション・業務】\n"
        "入社日　　　　【要確定】\n"
        "入社ポジション　Forward Deployed Engineer（FDEリード）\n"
        "業務内容　　　　顧客課題の深掘り〜設計・実装・検証、FDEチーム運営、セキュリティ方針の推進\n\n"
        "【勤務条件】（山田さん版に準拠・要最終確認）\n"
        "フレックス勤務／事業所（六本木一丁目駅徒歩4分）・リモート可／顧客訪問あり\n\n"
        "【賃金・雇用】\n"
        "年俸額　　【要確定】万円\n"
        "SO制度　　【要確定】（入社半年経過後等、Gradeに応じて付与）\n"
        "雇用形態　正社員　／　試用期間 6か月　／　期間の定めなし",
    )

    # 17 section message
    section_slide(prs, "メダップ一同からのメッセージ", "04")

    # 18 messages
    two_col_slide(
        prs,
        "入社を期待するメンバーからのメッセージ",
        "代表取締役 CEO　柳内 健",
        "メダップは、足元の事業成長と新規事業による伸びしろがあり、\n"
        "日本の地域医療に大きな貢献ができる可能性にあふれています。\n"
        "一方、顧客課題を技術で捉え、実装・検証まで届ける探索の力は、\n"
        "まだ足りていません。\n\n"
        "小山さんとお話しするなかで、「命に関わる領域で腰を据える」\n"
        "という想いと、現場に入り込み課題を構造化してやり切る姿勢が、\n"
        "まさに私たちが求めるFDEリードだと感じました。\n\n"
        "ぜひ参画いただき、FDEチーム立ち上げと事業成長、\n"
        "ひいては病院経営と地域医療への貢献を、一緒に実現させてください！",
        "Product　山田",
        "小山さんとお話しするなかで、手探りの現場で型を作り、\n"
        "関係者を巻き込みながらやり切る姿が強く印象に残りました。\n\n"
        "メダップのFDEはまだ立ち上げ期です。だからこそ、\n"
        "小山さんのような方と一緒に、顧客課題をプロダクト価値まで\n"
        "届けるチームをつくりたいと思っています。\n\n"
        "ぜひご参画をご検討ください。\n"
        "心よりお待ちしております。",
    )

    # 19 section summary
    section_slide(prs, "まとめ", "05")

    # 20 summary
    content_slide(
        prs,
        "まとめ",
        "● 病院経営は危機的状況にある\n\n"
        "● メダップはSaaS/AIで病院経営改善に取り組む一方、\n"
        "  顧客課題を技術で捉え完遂するFDEの力が不足している\n\n"
        "● 小山さんは、現場×構造化×立ち上げ×Secの経験と\n"
        "  「命に関わる領域で腰を据える」想いが、FDEリードに最もフィットする。\n"
        "  どうしても来ていただきたい！\n\n"
        "● 全国の将来の世代のためにも、質の高く・サステイナブルな地域医療を\n"
        "  一緒に作りたい",
    )

    prs.save(OUT)
    # 日本語名のコピーも置く（ローカル閲覧用）
    OUT_JP.write_bytes(OUT.read_bytes())
    return OUT


if __name__ == "__main__":
    path = build()
    print(f"Created: {path}")
    print(f"Also:    {OUT_JP}")
    print(f"Slides:  editable PPTX draft for review")
