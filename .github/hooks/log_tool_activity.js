#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const LOG_ROOT = path.resolve(__dirname, "..", "logs");

const MAX_OUTPUT_LINES = 30;

function emitEmptyObject() {
  process.stdout.write("{}\n");
}

function readStdin() {
  return new Promise(resolve => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", chunk => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", () => resolve(""));
  });
}

function parseToolArgs(rawToolArgs) {
  if (rawToolArgs == null) return {};
  if (typeof rawToolArgs === "object") return rawToolArgs;

  try {
    return JSON.parse(rawToolArgs);
  } catch {
    return { _rawToolArgs: rawToolArgs };
  }
}

function omitNullish(obj) {
  return Object.fromEntries(
    Object.entries(obj).filter(
      ([, value]) => value !== null && value !== undefined
    )
  );
}

function writeLogEntry(entry) {
  const currentDate = new Date().toISOString().slice(0, 10);
  const logDir = path.join(LOG_ROOT, currentDate);
  const logFile = path.join(logDir, "tool-activity.jsonl");

  try {
    fs.mkdirSync(logDir, { recursive: true });
  } catch {
    return;
  }

  try {
    fs.appendFileSync(logFile, `${JSON.stringify(entry)}\n`, "utf8");
  } catch {
    // Intentionally best-effort logging.
  }
}

function parseInputPayload(inputData) {
  try {
    return JSON.parse(inputData);
  } catch {
    // Match jq's tolerance for newline-delimited JSON payloads by
    // accepting a valid tool payload line when possible.
    const lines = String(inputData)
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(Boolean);
    let fallback = null;
    for (let i = 0; i < lines.length; i += 1) {
      try {
        const candidate = JSON.parse(lines[i]);
        if (candidate && typeof candidate === "object") {
          fallback = candidate;
          if (
            Object.prototype.hasOwnProperty.call(candidate, "toolName") ||
            Object.prototype.hasOwnProperty.call(candidate, "toolArgs") ||
            Object.prototype.hasOwnProperty.call(candidate, "toolResult")
          ) {
            return candidate;
          }
        }
      } catch {
        // Keep scanning candidate lines.
      }
    }
    return fallback;
  }
}

// --- Bash command markdown helpers ---

function formatTimestamp(iso) {
  if (!iso) return "";
  return iso
    .replace("T", " ")
    .replace(/\.\d+Z$/, " UTC")
    .replace(/Z$/, " UTC")
    .replace(/\+0000$/, " UTC");
}

function truncateOutput(text) {
  const lines = text.split("\n");
  if (lines.length <= MAX_OUTPUT_LINES) return { text, truncated: false };
  const kept = MAX_OUTPUT_LINES - 1;
  return {
    text: lines.slice(0, kept).join("\n"),
    truncated: true,
    omitted: lines.length - kept,
  };
}

function buildPreToolUseBlock(timestamp, toolArgs) {
  const command = typeof toolArgs.command === "string" ? toolArgs.command : "(no command)";
  const description = typeof toolArgs.description === "string" && toolArgs.description.trim()
    ? toolArgs.description.trim()
    : null;

  const meta = timestamp ? `> \`${formatTimestamp(timestamp)}\`` : "";
  const descLine = description ? `- ${description}` : `- *(no description)*`;

  const parts = [];
  if (meta) parts.push(meta, "");
  parts.push(descLine, "", "```bash", command, "```");

  return parts.join("\n");
}

function buildPostToolUseBlock(timestamp, toolArgs, toolResult) {
  const command = typeof toolArgs.command === "string" ? toolArgs.command : "(no command)";
  const description = typeof toolArgs.description === "string" && toolArgs.description.trim()
    ? toolArgs.description.trim()
    : null;

  const rawOutput = typeof toolResult?.textResultForLlm === "string"
    ? toolResult.textResultForLlm
    : "";

  const meta = timestamp ? `> \`${formatTimestamp(timestamp)}\`` : "";
  const descLine = description ? `- ${description}` : `- *(no description)*`;

  const outputTrimmed = rawOutput.trim();
  const { text: outputText, truncated, omitted } = truncateOutput(
    outputTrimmed.length > 0 ? outputTrimmed : "Output: (empty)"
  );
  const truncationNotice = truncated ? `\n\n... *(${omitted} lines omitted)*` : "";

  const parts = [];
  if (meta) parts.push(meta, "");
  parts.push(
    descLine,
    "",
    "```bash",
    command,
    "```",
    "",
    "```plaintext",
    outputText + truncationNotice,
    "```"
  );

  return parts.join("\n");
}

function writeBashCommandMd(parsedInput, hookEvent, toolArgs) {
  if (parsedInput.toolName !== "bash") return;

  const outputFile = path.join(LOG_ROOT, `${hookEvent}.md`);
  let timestampIso = new Date().toISOString();
  if (parsedInput.timestamp != null) {
    const tsNum = Number(parsedInput.timestamp);
    if (!isNaN(tsNum)) {
      timestampIso = new Date(tsNum).toISOString();
    } else {
      timestampIso = String(parsedInput.timestamp);
    }
  }

  const block = hookEvent === "preToolUse"
    ? buildPreToolUseBlock(timestampIso, toolArgs)
    : buildPostToolUseBlock(timestampIso, toolArgs, parsedInput.toolResult);

  try {
    fs.mkdirSync(LOG_ROOT, { recursive: true });
    fs.appendFileSync(outputFile, block + "\n\n---\n\n", "utf8");
  } catch (e) {
    process.stderr.write("Failed to write markdown log: " + e.message + "\n");
  }
}

function getNested(obj, pathParts) {
  let current = obj;
  for (let i = 0; i < pathParts.length; i += 1) {
    if (current == null || typeof current !== "object") {
      return null;
    }
    current = current[pathParts[i]];
  }
  return current === undefined ? null : current;
}

async function main() {
  const inputData = await readStdin();

  if (!/\S/.test(inputData)) {
    emitEmptyObject();
    return;
  }

  const parsedInput = parseInputPayload(inputData);
  if (parsedInput == null || typeof parsedInput !== "object") {
    emitEmptyObject();
    return;
  }

  const hookEvent = Object.prototype.hasOwnProperty.call(
    parsedInput,
    "toolResult"
  )
    ? "postToolUse"
    : "preToolUse";
  const toolArgs = parseToolArgs(parsedInput.toolArgs);
  const toolResultText = getNested(parsedInput, [
    "toolResult",
    "textResultForLlm",
  ]);
  const toolResultPreview =
    toolResultText == null ? null : String(toolResultText).slice(0, 500);

  const logEntry = omitNullish({
    loggedAt: new Date().toISOString(),
    sourceTimestamp:
      parsedInput.timestamp === undefined ? null : parsedInput.timestamp,
    hookEvent,
    cwd: parsedInput.cwd === undefined ? null : parsedInput.cwd,
    toolName: parsedInput.toolName === undefined ? null : parsedInput.toolName,
    toolArgs,
    bashCommand:
      parsedInput.toolName === "bash" &&
      toolArgs &&
      typeof toolArgs === "object"
        ? toolArgs.command || null
        : null,
    toolResultType: getNested(parsedInput, ["toolResult", "resultType"]),
    toolResultPreview,
  });

  writeLogEntry(logEntry);
  writeBashCommandMd(parsedInput, hookEvent, toolArgs);
  emitEmptyObject();
}

main()
  .catch(() => {
    emitEmptyObject();
  })
  .finally(() => {
    process.exit(0);
  });
