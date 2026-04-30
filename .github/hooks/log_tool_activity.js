#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const LOG_ROOT = path.resolve(__dirname, '..', 'logs');

function emitEmptyObject() {
  process.stdout.write('{}\n');
}

function readStdin() {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      data += chunk;
    });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', () => resolve(''));
  });
}

function parseToolArgs(rawToolArgs) {
  const raw = rawToolArgs === null || rawToolArgs === undefined ? '{}' : rawToolArgs;
  if (typeof raw !== 'string') {
    return { _rawToolArgs: raw };
  }

  try {
    return JSON.parse(raw);
  } catch {
    return { _rawToolArgs: raw };
  }
}

function omitNullish(obj) {
  return Object.fromEntries(
    Object.entries(obj).filter(([, value]) => value !== null && value !== undefined),
  );
}

function writeLogEntry(entry) {
  const currentDate = new Date().toISOString().slice(0, 10);
  const logDir = path.join(LOG_ROOT, currentDate);
  const logFile = path.join(logDir, 'tool-activity.jsonl');

  try {
    fs.mkdirSync(logDir, { recursive: true });
  } catch {
    return;
  }

  try {
    fs.appendFileSync(logFile, `${JSON.stringify(entry)}\n`, 'utf8');
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
      .map((line) => line.trim())
      .filter(Boolean);
    let fallback = null;
    for (let i = 0; i < lines.length; i += 1) {
      try {
        const candidate = JSON.parse(lines[i]);
        if (candidate && typeof candidate === 'object') {
          fallback = candidate;
          if (
            Object.prototype.hasOwnProperty.call(candidate, 'toolName') ||
            Object.prototype.hasOwnProperty.call(candidate, 'toolArgs') ||
            Object.prototype.hasOwnProperty.call(candidate, 'toolResult')
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

function getNested(obj, pathParts) {
  let current = obj;
  for (let i = 0; i < pathParts.length; i += 1) {
    if (current == null || typeof current !== 'object') {
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
  if (parsedInput == null || typeof parsedInput !== 'object') {
    emitEmptyObject();
    return;
  }

  const hookEvent = Object.prototype.hasOwnProperty.call(parsedInput, 'toolResult')
    ? 'postToolUse'
    : 'preToolUse';
  const toolArgs = parseToolArgs(parsedInput.toolArgs);
  const toolResultText = getNested(parsedInput, ['toolResult', 'textResultForLlm']);
  const toolResultPreview = toolResultText == null ? null : String(toolResultText).slice(0, 500);

  const logEntry = omitNullish({
    loggedAt: new Date().toISOString(),
    sourceTimestamp: parsedInput.timestamp === undefined ? null : parsedInput.timestamp,
    hookEvent,
    cwd: parsedInput.cwd === undefined ? null : parsedInput.cwd,
    toolName: parsedInput.toolName === undefined ? null : parsedInput.toolName,
    toolArgs,
    bashCommand:
      parsedInput.toolName === 'bash' && toolArgs && typeof toolArgs === 'object'
        ? toolArgs.command || null
        : null,
    toolResultType: getNested(parsedInput, ['toolResult', 'resultType']),
    toolResultPreview,
  });

  writeLogEntry(logEntry);
  emitEmptyObject();
}

main()
  .catch(() => {
    emitEmptyObject();
  })
  .finally(() => {
    process.exit(0);
  });
