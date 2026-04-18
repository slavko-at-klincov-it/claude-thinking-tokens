# Thinking Token Measurement in Claude Code + Opus 4.6

Empirische Analyse, April 2026. Basierend auf 12 kontrollierten Experimenten (6 Manual + 6 Adaptive) und Transcript-Analyse. Rev. 2: Korrekturen nach Peer-Review.

---

## 1. Architektur: Wer steuert was

Claude Code hat **drei unabhaengige Steuerungsebenen** fuer Thinking:

```
Ebene 1: settings.json (env vars)     → Claude Code CLI → API Request Parameter
Ebene 2: settings.json (effortLevel)  → Claude Code CLI → API effort Parameter
Ebene 3: ~/.claude/CLAUDE.md          → In Kontext injected → Beeinflusst Modellverhalten
```

### Ebene 1: API-Parameter (settings.json env)

```json
"CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING": "1",
"MAX_THINKING_TOKENS": "128000"
```

- `MAX_THINKING_TOKENS` setzt die **Obergrenze** (ceiling) fuer Thinking-Tokens pro API-Call
- `DISABLE_ADAPTIVE_THINKING` erzwingt **manuellen Modus** (feste Obergrenze statt dynamischer Zuweisung)
- Das Modell sieht diese Parameter nicht, sie werden von der CLI in den API-Request eingebaut
- Claude denkt **bis zu** diesem Budget, nicht zwingend das volle Budget
- Auf Opus 4.6 ist der manuelle Modus (`budget_tokens`) **deprecated**, funktioniert aber noch

**Hinweis zum Setup**: Unser Experiment erzwingt mit `DISABLE_ADAPTIVE_THINKING=1` den deprecated manuellen Modus. Auf Opus 4.6 ist Adaptive Thinking der empfohlene Default. Ein Vergleichsexperiment (Abschnitt 5) zeigt jedoch, dass der Modus keinen messbaren Einfluss auf die Thinking-Trigger-Rate hat.

### Ebene 2: Effort-Parameter (settings.json)

```json
"effortLevel": "max"
```

- Steuert den API `effort`-Parameter
- `max` ist das hoechste Level (nur auf Opus 4.6 verfuegbar)
- Beeinflusst, wie viel Aufwand Claude in Reasoning investiert
- Interagiert mit dem Thinking-Budget: hoehere Effort = tendenziell mehr Thinking innerhalb des Budgets
- `/effort max` im Chat setzt dies fuer die aktuelle Session

### Ebene 3: CLAUDE.md (Kontext-Anweisungen)

```markdown
# Output
- Minimize output tokens. No verbose narration around tool calls.
- Concise summary only when task is complete.
```

- CLAUDE.md wird als Prosa-Anweisung in den Kontext injected
- Das Modell liest und befolgt diese Instruktionen
- **Potentieller Konflikt**: "Minimize output tokens" koennte Thinking unterdruecken, weil das Modell "output" breit interpretiert
- CLAUDE.md steuert **Verhalten**, nicht API-Parameter
- Prompt-Anweisungen wie "ultrathink" oder "denke gruendlich nach" wirken auf derselben Ebene und koennen CLAUDE.md-Instruktionen situativ ueberwiegen

### Zusammenspiel

```
MAX_THINKING_TOKENS = 128000     ← Harte Obergrenze (API)
effortLevel = max                ← Tendenz zu mehr Thinking (API)
CLAUDE.md = "Minimize output"    ← Tendenz zu weniger Output (Kontext)
User Prompt = "ultrathink"       ← Situative Aufforderung, tief zu denken (Kontext)
```

Die API-Parameter setzen den **Rahmen**. Die Kontext-Anweisungen bestimmen, wie Claude diesen Rahmen **ausfuellt**. Ein Widerspruch zwischen "minimize output" (CLAUDE.md) und "think deeply" (Prompt) wird vom Modell situativ aufgeloest, wobei explizite User-Prompts typischerweise staerker wiegen als System-Instruktionen.

---

## 2. Herleitung: Vom Fehler zur Erkenntnis

Die folgenden Ergebnisse sind nicht linear entstanden. Der Weg enthielt drei Fehlschluesse die jeweils korrigiert werden mussten. Diese Korrekturen sind keine Schwaeche der Analyse, sondern ihr Kern: Jeder Fehler fuehrte zu einer praeziseren Messmethode.

### Schritt 1: Das Ausgangsproblem

Die urspruengliche Statusline verglich `context_window.total_output_tokens` (kumulativ ueber die gesamte Session) gegen `MAX_THINKING_TOKENS=64000` (Per-Turn-Limit). Das war konzeptuell falsch: ein Session-Zaehler gegen ein Per-Call-Budget. Der Balken wurde in jeder laengeren Session rot, unabhaengig davon ob Claude tatsaechlich viel dachte.

### Schritt 2: Erster Ansatz mit chars/4 und "Phantom-Thinking"

Nach der Redesign-Entscheidung (Rate Limits statt falscher Vergleich) wollten wir einen Thinking-Balken ergaenzen. Die erste Formel:

```
thinking_est = output_tokens - (visible_chars / 4)
```

Der Divisor 4.0 (chars pro Token) ist eine gaengige Daumenregel fuer englischen Text. Ergebnis:

| Prompt | Thinking? | output_tokens | text_chars | thinking_est (chars/4) |
|--------|-----------|---------------|------------|------------------------|
| CAP Theorem | OFF | 1,728 | 4,683 | **557** |
| TCP vs UDP | OFF | 474 | 1,209 | **171** |

**Problem**: Beide Prompts zeigten dreistellige "Thinking-Tokens" obwohl Thinking definitiv AUS war (kein `thinking` Content-Block im Transcript). Wir haben dieses "Phantom-Thinking" zu dem Zeitpunkt nicht als Kalibrierungsfehler erkannt, sondern als erwartetes Rauschen akzeptiert.

### Schritt 3: Der "Summary"-Fehlschluss

Parallel dazu untersuchten drei Research-Agents die Anthropic API und Community-Quellen. Ihre Ergebnisse:

- "Auf Claude 4.x wird Thinking summarized zurueckgegeben"
- "output_tokens im API-Response enthaelt nur die Summary"
- "Echtes Thinking ist 10-17x hoeher als was die API meldet"

**Wir haben diese Schlussfolgerung unkritisch uebernommen** und den Thinking-Balken als `(summary, est.)` gelabelt. Die Agents hatten eine Teilwahrheit geliefert: der sichtbare Thinking-**Text** im Content-Block IST tatsaechlich eine Summary (oder komplett leer/redacted). Aber wir haben faelschlicherweise geschlossen, dass `usage.output_tokens` ebenfalls nur Summary-Tokens zaehlt.

### Schritt 4: Der Widerspruch

Auf die Frage "das bedeutet also keine Zahlen?" (weil Summary-Werte nutzlos waeren fuer einen Balken) folgte eine erneute, gruendlichere Analyse. Der entscheidende Gedanke:

> Wenn `output_tokens` NUR Summary-Tokens enthalten wuerde, warum zeigen Non-Thinking-Cases (CAP Theorem, TCP vs UDP) dann "Phantom-Thinking"? Diese Calls HABEN kein Thinking, also muss `output_tokens` dort exakt den sichtbaren Text-Tokens entsprechen.

Daraus folgt: `output_tokens` bei Non-Thinking-Calls = sichtbare Text-Tokens. Das heisst, der chars-per-token Divisor laesst sich **empirisch bestimmen**, indem man Non-Thinking-Calls als Baseline nutzt.

### Schritt 5: Kalibrierung und Beweis

Aus den Non-Thinking-Baselines:

| Prompt | output_tokens | text_chars | chars/token |
|--------|---------------|------------|-------------|
| TCP vs UDP | 474 | 1,209 | **2.55** |
| CAP Theorem | 1,728 | 4,683 | **2.71** |

Der echte Divisor fuer Markdown-Text ist ~2.7, nicht 4.0. Die Daumenregel 4.0 gilt fuer reinen Prosa-Text, Markdown mit Headings, Code-Blocks und Listen tokenisiert dichter.

Validierung mit kalibriertem Divisor:

| Prompt | Thinking? | thinking_est (chars/4) | thinking_est (chars/2.7) |
|--------|-----------|------------------------|--------------------------|
| TCP vs UDP | OFF | 171 (falsch, Phantom) | **26 ≈ 0** ✓ |
| CAP Theorem | OFF | 557 (falsch, Phantom) | **-6 ≈ 0** ✓ |
| Fixed-point | ON | 1,424 | **700** |
| Flusspuzzle | ON | 5,327 | **5,124** |

Das "Phantom-Thinking" verschwindet. Non-Thinking-Cases konvergieren auf ~0 (±26 Tokens). Dieser Konvergenz-Beweis schliesst gleichzeitig aus, dass `output_tokens` nur Summaries enthaelt, denn: Summary-Tokens wuerden bei Thinking-Calls deutlich unter dem vollen Wert liegen, und die Kalibrierung gegen Non-Thinking wuerde dann systematisch zu hohe (nicht zu niedrige) Werte fuer Thinking-Calls liefern.

### Schritt 6: Label-Korrektur

Das Label wurde von `(summary, est.)` zu `(heavy/moderate/light)` geaendert. Die Zahlen sind real, nicht Summaries. Der Kommentar im Script wurde entsprechend aktualisiert.

### Schritt 7: Peer-Review und drei weitere Korrekturen

Ein Peer-Review deckte drei verbleibende Ungenauigkeiten auf:

1. **"10-17x widerlegt" war falsch formuliert**: Der Community-Claim beschreibt korrekt, dass Tools die aus Content-Bloecken zaehlen massiv unterzaehlen. Unsere Erkenntnis widerlegt das nicht, sondern loest es auf: `usage.output_tokens` (was wir nutzen) enthaelt die vollen Tokens. Content-Block-Text (was manche Tools zaehlen) ist Summary/redacted. Beides stimmt, verschiedene Messpunkte.

2. **Thinking-Block ≠ echtes Reasoning**: Das Paper erklaerte nicht, dass der `thinking`-Content-Block im Transcript eine Summary (oder leer) ist, nicht das Original-Reasoning. Ein Leser koennte annehmen, der Text im `thinking`-Feld sei das echte Denken. Ist er nicht.

3. **Deprecated-Mode-Hypothese**: Die Vermutung, der deprecated manuelle Modus erklaere die niedrige Thinking-Rate, wurde durch ein Gegenexperiment geprueft: gleiche 6 Prompts mit Adaptive Thinking → identische 2/6 Trigger-Rate. Hypothese widerlegt.

---

## 3. Ergebnis: Zwei Messpunkte, ein Missverstaendnis

### Der "10-17x Undercount"-Claim: aufgeloest, nicht widerlegt

Community-Tools und Blog-Posts berichten, dass JSONL-Logs Thinking-Tokens 10-17x unterzaehlen. Dieser Claim beschreibt ein **reales Tooling-Problem**, keinen Mythos. Die Verwirrung entsteht durch zwei verschiedene Messpunkte:

| Messpunkt | Was er misst | Korrektheit |
|-----------|-------------|-------------|
| `usage.output_tokens` (API-Response-Feld) | **Volle** Thinking-Tokens + sichtbarer Output | Korrekt, vollstaendig |
| Content-Block-Text (thinking + text Felder) | **Zusammengefasster/redacted** Thinking-Text + sichtbarer Output | Massiv unterzaehlt |

Anthropic-Dokumentation (Extended Thinking):
> "Output tokens (billed): The original thinking tokens that Claude generated internally."
> "Output tokens (visible): The summarized thinking tokens you see in the response."

**Unsere Erkenntnis**: `usage.output_tokens` im JSONL-Transcript kommt direkt aus dem API-Response und enthaelt die vollen Tokens. Tools die stattdessen aus Content-Bloecken zaehlen, unterzaehlen tatsaechlich massiv. Beide Seiten haben recht, der Fehler steckt in der Messmethode mancher Tools, nicht in der API.

**Verifiziert**: Fuer den River-Puzzle-Call (Thinking ON):
- `usage.output_tokens` = 5,750 (aus API-Response, im JSONL gespeichert)
- Content-Block-Schaetzung (chars/2.7) = 627
- Faktor: **9.2x** (im Bereich des Community-Claims von 10-17x)

### Beweis: Kalibrations-Experiment

**Methode**: 6 Prompts unterschiedlicher Komplexitaet an Opus 4.6 (effort=max, budget=128k). Analyse der Transcripts.

**Schritt 1 - Kalibrierung**: Bei Prompts OHNE Thinking ist `usage.output_tokens` = sichtbare Text-Tokens. Daraus laesst sich das reale chars-per-token Verhaeltnis bestimmen:

| Prompt (kein Thinking) | output_tokens | text_chars | chars/token |
|------------------------|---------------|------------|-------------|
| TCP vs UDP             | 474           | 1,209      | 2.55        |
| CAP Theorem Analyse    | 1,728         | 4,683      | 2.71        |

**Ergebnis**: Fuer Markdown/technischen Text gilt ~2.7 chars/token (nicht 4.0 wie oft angenommen).

**Schritt 2 - Validierung**: Mit dem kalibrierten Divisor (2.7) pruefen ob Non-Thinking-Faelle korrekt auf ~0 Thinking gehen:

| Prompt | Thinking? | output_tokens | text_chars | visible_tok (chars/2.7) | thinking_est |
|--------|-----------|---------------|------------|-------------------------|-------------|
| TCP vs UDP | OFF | 474 | 1,209 | 448 | **26 ≈ 0** ✓ |
| CAP Theorem | OFF | 1,728 | 4,683 | 1,734 | **-6 ≈ 0** ✓ |
| Fixed-point Beweis | ON | 2,927 | 6,012 | 2,227 | **700** |
| Flusspuzzle+Fuchs | ON | 5,750 | 1,691 | 626 | **5,124** |

Non-Thinking-Faelle gehen exakt auf ~0. Das bestaetigt: `usage.output_tokens` enthaelt die vollen Thinking-Tokens, und unsere Formel extrahiert sie korrekt.

### Implikation

Die Formel `thinking_tokens ≈ output_tokens - (visible_chars / 2.7)` liefert **reale** Thinking-Token-Werte, vorausgesetzt man nimmt `output_tokens` aus dem `usage`-Objekt (nicht aus Content-Block-Zaehlung).

---

## 4. Thinking-Detection: Definitiver Indikator

### Methode

Das Claude Code Transcript (JSONL) speichert pro API-Call Content-Blocks mit Typ-Annotation. Wenn Extended Thinking aktiv war, existiert ein Block mit `"type": "thinking"`.

```json
{"type": "thinking", "thinking": "...", "signature": "..."}
```

**Wichtig: Der Text im `thinking`-Feld ist NICHT das echte Reasoning.** Bei Claude 4.x Modellen wird das Original-Thinking intern generiert und von einem separaten Modell zu einer Summary zusammengefasst. Der User sieht nie das volle Thinking. In vielen Claude Code Transcripts ist der Thinking-Text sogar komplett leer (0 Chars, redacted). Abgerechnet werden aber die vollen Original-Thinking-Tokens, die in `usage.output_tokens` enthalten sind.

Unsere Kalibrierungsformel nutzt genau diese Diskrepanz: `usage.output_tokens` (voll) minus sichtbarer Text (nur `text`- und `tool_use`-Blocks, nicht `thinking`-Blocks) ergibt die echten Thinking-Tokens.

### Die 4 Saeulen

| # | Metrik | Quelle | Zuverlaessigkeit | Bedeutung |
|---|--------|--------|-------------------|-----------|
| 1 | `output_tokens` | usage-Objekt | 100% | Volle Output-Tokens inkl. ALLER Thinking |
| 2 | `text_chars` | text/tool_use content blocks | 100% | Sichtbarer Text-Output (ohne Thinking) |
| 3 | `cache_read_input_tokens` | usage-Objekt | 100% | Konversationshistorie (Kontext-Last) |
| 4 | **`has_thinking`** | content_types | **100%** | **Definitiver ON/OFF-Indikator** |

Saeule 1-3 sind immer vorhanden. Saeule 4 ist nur bei aktivem Thinking praesent. Die Differenz aus Saeule 1 und 2 (kalibriert mit /2.7) ergibt die Thinking-Token-Menge.

**Achtung**: Saeule 2 (`text_chars`) zaehlt bewusst NUR `text`- und `tool_use`-Blocks, nicht den `thinking`-Block. Der `thinking`-Block enthaelt eine Summary (oder ist leer), die wir nicht mitzaehlen wollen, weil wir die Differenz zum vollen `usage.output_tokens` messen.

### Intensitaets-Klassifikation

Basierend auf dem Verhaeltnis `output_tokens / visible_tokens`:

| Ratio | Intensitaet | Bedeutung |
|-------|-------------|-----------|
| < 2.0 | Kein/minimal | Kein signifikantes Thinking |
| 2.0 - 5.0 | Light | Kurzes Reasoning |
| > 5.0 | Heavy | Intensives Deep Thinking |

---

## 5. Experiment: Adaptive vs Manual Thinking

### Hypothese

Der deprecated manuelle Modus (`budget_tokens`) koennte erklaeren, warum nur 2/6 Prompts Thinking triggern. In Adaptive Thinking wuerde das Modell aktiv ueber Thinking-Bedarf entscheiden und haeufiger Thinking aktivieren.

### Methode

Gleiche 6 Prompts, einmal mit `DISABLE_ADAPTIVE_THINKING=1` (Manual), einmal mit `DISABLE_ADAPTIVE_THINKING=0` (Adaptive). Alles andere identisch (`effortLevel=max`).

### Ergebnisse

| Prompt | Manual: Think? | Manual: OUT | Adaptive: Think? | Adaptive: OUT |
|--------|----------------|-------------|-------------------|---------------|
| 2+2 trivial | OFF | 6 | OFF | 6 |
| 3 languages | OFF | 17 | OFF | 17 |
| TCP vs UDP | OFF | 474 | OFF | 402 |
| CAP theorem deep | OFF | 1,728 | OFF | 1,835 |
| Fixed-point proof | **ON** | 2,927 | **ON** | 3,165 |
| River puzzle+fox | **ON** | 5,750 | **ON** | 4,223 |

**Manual: 2/6 Thinking-Trigger. Adaptive: 2/6 Thinking-Trigger. Identisch.**

### Schlussfolgerung

Die Hypothese wurde **nicht bestaetigt**. Der deprecated manuelle Modus erklaert NICHT die niedrige Thinking-Trigger-Rate. Opus 4.6 trifft in beiden Modi die gleiche Entscheidung, welche Prompts Extended Thinking benoetigen. Die Thinking-Aktivierung ist prompt-abhaengig, nicht modus-abhaengig.

---

## 6. Server-seitige Thinking-Allokation (Issue #42796)

Eine unabhaengige Analyse (GitHub Issue [anthropics/claude-code#42796](https://github.com/anthropics/claude-code/issues/42796)) mit 17,871 Thinking-Blocks und 234,760 Tool-Calls deckt auf, dass Anthropic Thinking-Budgets **server-seitig allokiert und throttelt**. Dies veraendert die Interpretation unserer Findings grundlegend.

### Kernbefunde aus #42796

**Thinking-Tiefe sank um 73%** zwischen Januar und Maerz 2026:

| Zeitraum | Median Thinking (chars) | vs Baseline |
|----------|------------------------|-------------|
| Jan 30 - Feb 8 (Baseline) | ~2,200 | - |
| Ende Februar | ~720 | -67% |
| Maerz (nach Redaction) | ~600 | -73% |

Die Reduktion begann **vor** der Thinking-Redaction (`redact-thinking-2026-02-12`), was zeigt: Anthropic reduzierte die Thinking-Allokation serverseitig, unabhaengig von Client-Konfiguration.

**Thinking ist load-abhaengig**: Die Allokation variiert je nach Serverauslastung. Zu US-Stosszeiten (17h PST) sinkt die Thinking-Tiefe auf den niedrigsten Wert.

**Qualitaets-Impact ist katastrophal**: Read:Edit Ratio sank von 6.6 auf 2.0 (-70%), 33% aller Edits wurden ohne vorheriges Lesen der Datei durchgefuehrt, Stop-Hook-Verletzungen stiegen von 0 auf 173 in 17 Tagen, User-Interrupts stiegen 12x.

### Implikation fuer unsere Findings

Unsere Beobachtung "max 17% Thinking-Budget genutzt" ist moeglicherweise **kein Zeichen von Modell-Effizienz, sondern von Server-Throttling**:

| Unsere Interpretation (alt) | Neue Interpretation (nach #42796) |
|-----------------------------|-----------------------------------|
| Claude braucht nur ~22k Tokens zum Denken | Server allokiert moeglicherweise nicht mehr |
| 128k Budget ist Overkill | 128k Budget ist Client-Ceiling, Server ignoriert es |
| Nur 2/6 Prompts brauchen Thinking | Server entscheidet moeglicherweise nicht der Prompt |
| chars/2.7 Formel misst echtes Thinking | Formel misst was ALLOKIERT wurde, nicht was GEBRAUCHT wuerde |

### Signature-Feld als Thinking-Proxy

Issue #42796 nutzt die Signature-Laenge als Proxy fuer Thinking-Tiefe (Pearson r = 0.971 auf 7,146 Blocks mit sichtbarem Thinking-Text). Wir konnten diese Korrelation **nicht reproduzieren**: 99.2% unserer 393 Thinking-Blocks sind redacted (April 2026, post-Redaction). Unsere gemessene Korrelation Signature vs output_tokens liegt bei r = 0.68 (moderater Zusammenhang). Die Signature-Laenge ist ein sekundaerer Indikator, kein Ersatz fuer unsere Formel.

### Was wir weiterhin messen koennen

Unsere chars/2.7 Formel und die Thinking-Detection via content_types bleiben korrekt fuer die Frage: **"Wie viel Thinking wurde in diesem Turn allokiert?"** Die Frage die wir NICHT beantworten koennen: **"Wie viel Thinking haette Claude gebraucht?"**

---

## 7. Unerwartete Befunde

### Nur 2 von 6 Prompts triggerten Thinking (in BEIDEN Modi)

Trotz `effort=max` und `budget=128000` aktivierte Opus 4.6 Thinking identisch in Manual und Adaptive Mode, nur fuer:
- Logik-Puzzle mit Twist (heavy, 5.1k tokens)
- Mathematischer Beweis (light, 700 tokens)

Vier Prompts, darunter eine komplexe CAP-Theorem-Analyse, liefen OHNE Thinking. Im Kontext von Abschnitt 6 ist unklar ob dies Modell-Effizienz oder Server-Throttling widerspiegelt.

### Max Thinking: 22.3k von 128k (17%)

Ein gezielter Maximum-Thinking-Test (5-teiliger formaler Beweis eines verteilten Lock-Protokolls mit Byzantine-Fehleranalyse und TLA+-Spezifikation) erreichte 22,334 geschaetzte Thinking-Tokens (17.4% des 128k Budgets). Ueber hunderte API-Calls in einer Woche lag das Maximum bei 27.7k output_tokens (22%). Im Kontext von Abschnitt 6 moeglicherweise ein Server-Cap, nicht ein Modell-Limit.

### chars/token Ratio ist 2.7, nicht 4.0

Die weit verbreitete Annahme von ~4 chars/token basiert auf reinem englischen Prosa-Text. Fuer Markdown mit Headings, Code-Blocks, Listen und Sonderzeichen liegt der Wert bei ~2.7. Dieser Unterschied fuehrt bei falscher Annahme zu ~50% Ueberschaetzung der Thinking-Tokens.

---

## 8. Praktische Implementierung: Statusline

Die Erkenntnisse sind in `~/.claude/statusline.sh` implementiert:

```
5h Limit █░░░░░░░░░ 5% 2h | 7d Limit ██░░░░░░░░ 28% Fr 11:00 | ctx 13%
last API-Call 1.0k | session 515.8k | cached history 141.8k
thinking: ON ████░░░░░░ 40% ~51.2k/128.0k (heavy)
```

- Zeile 1: Rate Limits (5h/7d), Context-Window-Auslastung
- Zeile 2: Neuer Token-Verbrauch (ohne Cache-Reads), Session-Total, Cache-Last
- Zeile 3: Thinking ON/OFF (definitiv), Balken gegen 128k, geschaetzte Tokens, Intensitaet

Datenquelle fuer Thinking: `usage.output_tokens` aus dem JSONL-Transcript (= volle Tokens), nicht aus Content-Block-Text (= Summary/redacted).

---

## 9. Offene Fragen

1. **Server-Throttle oder Modell-Effizienz?** Unsere Tests zeigen max 17% Thinking-Budget-Nutzung. Issue #42796 dokumentiert serverseitiges Throttling. Ohne Zugang zu Anthropics Infrastruktur-Metriken koennen wir nicht unterscheiden ob Claude wenig denkt weil es effizient ist, oder weil der Server wenig allokiert. Ein Zeit-basiertes Experiment (gleiche Prompts zu verschiedenen Tageszeiten) koennte Klarheit schaffen: wenn Thinking zu Off-Peak-Zeiten hoeher ist, spricht das fuer Server-Throttle.

2. **Ist die Thinking-Allokation plan-abhaengig?** Pro-Subscription vs Max-Subscription koennten unterschiedliche Thinking-Budgets haben. Issue #42796 dokumentiert $42k geschaetzte Bedrock-Kosten bei $400 Subscription, was auf massive Subventionierung hindeutet. Anthropic koennte Thinking reduzieren um Kosten zu kontrollieren.

3. **Konfligiert "Minimize output tokens" mit Thinking?** Die CLAUDE.md-Anweisung koennte Thinking unterdruecken. Experiment mit/ohne diese Instruktion steht aus.

4. **Unterschied print-mode vs interaktiv**: Im interaktiven Modus (Hauptsession) war Thinking haeufiger aktiv als in `claude -p`. Moeglicherweise unterschiedliche API-Parameter oder System-Prompt-Unterschiede.

---

## Methodik

- 12 kontrollierte Prompts: 6 via Manual Mode + 6 via Adaptive Mode, jeweils `claude -p` an Opus 4.6
- Transcript-Analyse (JSONL) fuer content_types, usage.output_tokens, text_chars
- Selbst-Kalibrierung via Non-Thinking-Baseline (chars/token = 2.7)
- Kreuzvalidierung gegen 7-Tage-Transcripthistorie
- 55/55 automatisierte Tests PASS (Statusline-Verifizierung)
- Settings: `MAX_THINKING_TOKENS=128000`, `effortLevel=max`

### Revision 2 Korrekturen (nach Peer-Review)

1. **"10-17x Undercount" aufgeloest statt widerlegt**: Beide Messpunkte (usage vs Content-Blocks) sind korrekt, der Unterschied ist die Messmethode
2. **Thinking-Text = Summary/redacted, nicht echtes Reasoning**: Explizit klargestellt, dass `thinking`-Block im Transcript gekuerzt/leer ist
3. **Adaptive vs Manual Experiment hinzugefuegt**: Hypothese dass deprecated Mode die Trigger-Rate erklaert wurde empirisch widerlegt (2/6 in beiden Modi)
