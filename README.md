# Claude Code Thinking Token Measurement

Empirical analysis of how to measure Extended Thinking token usage in Claude Code CLI with Opus 4.6, plus a statusline script that displays rate limits, token usage, and thinking activity in real time.

## Background

Claude Code's statusline JSON provides token usage data, but Anthropic does not expose thinking tokens as a separate field. The `usage.output_tokens` value bundles thinking and visible output together, and the visible thinking text in transcripts is either summarized or redacted.

This project documents how we discovered that `usage.output_tokens` contains the **full** thinking token count (not just the summary), and how to extract thinking tokens via calibrated subtraction.

## Key Finding

```
thinking_tokens = output_tokens - (visible_text_chars / 2.7)
```

- `output_tokens` from the `usage` object in Claude Code's JSONL transcript contains full thinking tokens (verified against non-thinking baselines)
- The divisor 2.7 (chars per token) was empirically calibrated from non-thinking API calls producing markdown output
- With this calibration, non-thinking calls correctly yield ~0 thinking tokens (within +/-26 token tolerance)
- The `content_types` array in the transcript provides a 100% reliable ON/OFF indicator for thinking activation

The commonly cited "10-17x undercount" claim is not wrong, it describes a different measurement: tools that count tokens from content block text (which IS summarized/redacted) will indeed massively undercount. Tools that read `usage.output_tokens` directly (like this statusline) get the real numbers.

## Repository Contents

| File | Description |
|------|-------------|
| [ANALYSIS.md](ANALYSIS.md) | Full research paper with methodology, calibration proof, and corrections |
| [statusline.sh](statusline.sh) | Claude Code statusline script (3-line display) |
| [test.sh](test.sh) | Automated test suite (55 tests covering all values) |

## Statusline

The statusline displays three lines of information in the Claude Code CLI:

```
5h Limit ██░░░░░░░░ 14% 2h51m | 7d Limit ██░░░░░░░░ 28% Fr. 11:00 | ctx 13%
last API-Call 960 | session 541.4k | cached history 180.7k
thinking: ON ░░░░░░░░░░ 4% ~5.1k/128.0k (heavy)
```

**Line 1**: Rate limits (5-hour rolling window, 7-day rolling window) with color-coded bars and reset countdown/date, plus context window usage percentage.

**Line 2**: New tokens consumed by the last API call (excluding cache reads), cumulative session tokens, and cached conversation history size.

**Line 3**: Definitive thinking ON/OFF detection (from transcript content types), thinking token bar against the configured budget (128k), estimated thinking tokens, and intensity classification (light/moderate/heavy).

### Color Thresholds

| Range | Color |
|-------|-------|
| 0-40% | Green |
| 41-70% | Yellow |
| 71-90% | Red |
| 91%+ | Bold red |

### Quick Install

```bash
# 1. Install jq if not present
brew install jq        # macOS
# apt install jq       # Linux

# 2. Clone and install
git clone https://github.com/slavko-at-klincov-it/claude-thinking-tokens.git
cd claude-thinking-tokens
./install.sh

# 3. Start a new Claude Code session
claude
```

The install script copies `statusline.sh` to `~/.claude/` and merges the statusline config into your existing `~/.claude/settings.json` (preserving all other settings).

To remove: `./install.sh remove`

### Manual Installation

If you prefer to do it yourself:

1. Copy `statusline.sh` to `~/.claude/statusline.sh`
2. Make executable: `chmod +x ~/.claude/statusline.sh`
3. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

### Dependencies

- `jq` (JSON processor, required)
- `date` (GNU or BSD, included in macOS/Linux)
- Bash 4+

## Experiment Setup

All experiments were run with Claude Opus 4.6 (1M context) using:

```json
{
  "env": {
    "MAX_THINKING_TOKENS": "128000",
    "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING": "1"
  },
  "effortLevel": "max"
}
```

12 controlled prompts (6 manual mode + 6 adaptive mode) ranging from trivial ("What is 2+2?") to complex (distributed consensus protocol design, mathematical proofs). See [ANALYSIS.md](ANALYSIS.md) for full results.

## Running Tests

```bash
chmod +x test.sh
./test.sh
```

Expected output: 55/55 PASS. The test suite covers helper functions, synthetic JSON inputs, real transcript data, edge cases, and calibration validation.

## Related

- [GitHub Issue #11535](https://github.com/anthropics/claude-code/issues/11535): Feature request for granular token usage in Claude Code statusline
- [Anthropic Extended Thinking Docs](https://platform.claude.com/docs/en/build-with-claude/extended-thinking)
- [Claude Code Statusline Docs](https://code.claude.com/docs/en/statusline)

## License

MIT
