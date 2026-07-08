import { getLanguageFromPath, highlightCode, renderDiff as classicRenderDiff, theme } from "@oh-my-pi/pi-coding-agent";
import {
	BG_RESET,
	bgAnsi,
	type DiffPrefix,
	FG_RESET,
	PALETTES,
	type ParsedDiffLine,
	parseDiffLine,
	type RenderDiffFn,
	replaceTabs,
} from "./diff.ts";

// Hunks highlight as two file views (context+removed / context+added) so changed lines tokenize with real surrounding context, diffs.nvim-style.
function buildHighlights(parsedLines: readonly (ParsedDiffLine | null)[], filePath: string | undefined): Map<number, string> {
	const highlights = new Map<number, string>();
	const lang = filePath ? getLanguageFromPath(filePath) : undefined;
	if (!lang) return highlights;

	let run: number[] = [];
	const flush = () => {
		if (run.length === 0) return;
		const oldIdx: number[] = [];
		const oldTexts: string[] = [];
		const newIdx: number[] = [];
		const newTexts: string[] = [];
		for (const i of run) {
			const parsed = parsedLines[i];
			if (!parsed) continue;
			const content = replaceTabs(parsed.content);
			if (parsed.prefix === "-") {
				oldIdx.push(i);
				oldTexts.push(content);
			} else if (parsed.prefix === "+") {
				newIdx.push(i);
				newTexts.push(content);
			} else {
				oldIdx.push(i);
				oldTexts.push(content);
				newIdx.push(i);
				newTexts.push(content);
			}
		}
		if (newTexts.length > 0) {
			const highlighted = highlightCode(newTexts.join("\n"), lang);
			for (let k = 0; k < newIdx.length; k++) {
				const idx = newIdx[k];
				if (idx !== undefined) highlights.set(idx, highlighted[k] ?? newTexts[k] ?? "");
			}
		}
		if (oldTexts.length > 0) {
			const highlighted = highlightCode(oldTexts.join("\n"), lang);
			for (let k = 0; k < oldIdx.length; k++) {
				const idx = oldIdx[k];
				if (idx !== undefined && !highlights.has(idx)) highlights.set(idx, highlighted[k] ?? oldTexts[k] ?? "");
			}
		}
		run = [];
	};

	for (let i = 0; i < parsedLines.length; i++) {
		const parsed = parsedLines[i] ?? null;
		const isCollapse = parsed !== null && parsed.prefix === " " && (parsed.content === "..." || parsed.content === "…");
		if (parsed && !isCollapse) run.push(i);
		else flush();
	}
	flush();
	return highlights;
}

function changedSpan(a: string, b: string): { start: number; endA: number; endB: number } | null {
	const minLen = Math.min(a.length, b.length);
	let start = 0;
	while (start < minLen && a[start] === b[start]) start++;
	let suffix = 0;
	while (suffix < minLen - start && a[a.length - 1 - suffix] === b[b.length - 1 - suffix]) suffix++;
	const endA = a.length - suffix;
	const endB = b.length - suffix;
	if (start >= endA && start >= endB) return null;
	return { start, endA, endB };
}

function overlayEmph(text: string, from: number, to: number, emphBg: string, lineBg: string): string {
	if (to <= from) return text;
	let out = "";
	let col = 0;
	let i = 0;
	let emphOpen = false;
	while (i < text.length) {
		if (text.charCodeAt(i) === 0x1b) {
			const match = /^\x1b\[[0-9;]*m/.exec(text.slice(i));
			if (match) {
				out += match[0];
				i += match[0].length;
				continue;
			}
		}
		if (!emphOpen && col === from) {
			out += emphBg;
			emphOpen = true;
		} else if (emphOpen && col === to) {
			out += lineBg;
			emphOpen = false;
		}
		out += text[i];
		i++;
		col++;
	}
	if (emphOpen) out += lineBg;
	return out;
}

function renderRich(diffText: string, filePath: string | undefined): string {
	const palette = theme.isLight ? PALETTES.light : PALETTES.dark;
	const addBg = bgAnsi(palette.add);
	const addEmphBg = bgAnsi(palette.addEmph);
	const delBg = bgAnsi(palette.del);
	const delEmphBg = bgAnsi(palette.delEmph);
	const addGutterFg = theme.getFgAnsi("toolDiffAdded");
	const delGutterFg = theme.getFgAnsi("toolDiffRemoved");

	const lines = diffText.replaceAll("\r", "").split("\n");
	const parsedLines = lines.map(parseDiffLine);
	const lineNumberWidth = parsedLines.reduce((width, parsed) => {
		const lineNumber = parsed?.lineNum.trim() ?? "";
		return Math.max(width, lineNumber.length);
	}, 3);
	const highlights = buildHighlights(parsedLines, filePath);

	let prevLineNum = "";
	const formatGutter = (marker: DiffPrefix, lineNum: string): string | null => {
		if (lineNum.trim().length === 0) {
			prevLineNum = "";
			return null;
		}
		const trimmed = lineNum.trim();
		const displayNum = trimmed === prevLineNum ? "" : trimmed;
		prevLineNum = trimmed;
		const markerText = marker.trim();
		const gutterText = markerText && displayNum ? `${markerText}${displayNum}` : displayNum || markerText;
		return `${gutterText.padStart(lineNumberWidth + 1, " ")}│`;
	};

	const bodyFor = (index: number, parsed: ParsedDiffLine): string =>
		highlights.get(index) ?? replaceTabs(parsed.content);

	const emitChanged = (index: number, parsed: ParsedDiffLine, body: string): string => {
		const added = parsed.prefix === "+";
		const lineBg = added ? addBg : delBg;
		const gutterFg = added ? addGutterFg : delGutterFg;
		const gutter = formatGutter(parsed.prefix, parsed.lineNum);
		if (gutter === null) return `${lineBg}${gutterFg}${parsed.prefix}${FG_RESET}${body}${BG_RESET}`;
		return `${lineBg}${gutterFg}${gutter}${FG_RESET}${body}${BG_RESET}`;
	};

	const emitContext = (index: number, parsed: ParsedDiffLine): string => {
		const body = bodyFor(index, parsed);
		const gutter = formatGutter(" ", parsed.lineNum);
		if (gutter === null) return theme.fg("toolDiffContext", `${parsed.prefix}${body}`);
		return theme.fg("toolDiffContext", `${gutter}${body}`);
	};

	const result: string[] = [];
	let i = 0;
	while (i < lines.length) {
		const parsed = parsedLines[i] ?? null;

		if (!parsed) {
			prevLineNum = "";
			const trimmed = (lines[i] ?? "").trim();
			const isGapRow = trimmed.length === 0 || trimmed === "..." || trimmed === "…";
			result.push(theme.fg("toolDiffContext", isGapRow ? "…" : replaceTabs(lines[i] ?? "")));
			i++;
			continue;
		}

		if (parsed.prefix === "-") {
			const removed: number[] = [];
			while (i < lines.length && parsedLines[i]?.prefix === "-") {
				removed.push(i);
				i++;
			}
			const added: number[] = [];
			while (i < lines.length && parsedLines[i]?.prefix === "+") {
				added.push(i);
				i++;
			}

			const removedFirst = removed[0];
			const addedFirst = added[0];
			if (removed.length === 1 && added.length === 1 && removedFirst !== undefined && addedFirst !== undefined) {
				const removedParsed = parsedLines[removedFirst];
				const addedParsed = parsedLines[addedFirst];
				if (removedParsed && addedParsed) {
					const rawRemoved = replaceTabs(removedParsed.content);
					const rawAdded = replaceTabs(addedParsed.content);
					const span = changedSpan(rawRemoved, rawAdded);
					let removedBody = bodyFor(removedFirst, removedParsed);
					let addedBody = bodyFor(addedFirst, addedParsed);
					if (span) {
						removedBody = overlayEmph(removedBody, span.start, span.endA, delEmphBg, delBg);
						addedBody = overlayEmph(addedBody, span.start, span.endB, addEmphBg, addBg);
					}
					result.push(emitChanged(removedFirst, removedParsed, removedBody));
					result.push(emitChanged(addedFirst, addedParsed, addedBody));
				}
			} else {
				for (const idx of removed) {
					const parsedRemoved = parsedLines[idx];
					if (parsedRemoved) result.push(emitChanged(idx, parsedRemoved, bodyFor(idx, parsedRemoved)));
				}
				for (const idx of added) {
					const parsedAdded = parsedLines[idx];
					if (parsedAdded) result.push(emitChanged(idx, parsedAdded, bodyFor(idx, parsedAdded)));
				}
			}
		} else if (parsed.prefix === "+") {
			result.push(emitChanged(i, parsed, bodyFor(i, parsed)));
			i++;
		} else {
			result.push(emitContext(i, parsed));
			i++;
		}
	}

	return result.join("\n");
}

export const richRenderDiff: RenderDiffFn = (diffText, options) => {
	try {
		if (theme.getColorMode() !== "truecolor") return classicRenderDiff(diffText, options);
		return renderRich(diffText, options?.filePath);
	} catch {
		return classicRenderDiff(diffText, options);
	}
};
