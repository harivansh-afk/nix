/**
 * rich-diff: diffs.nvim-style rendering for omp edit/apply_patch diffs.
 *
 * omp has no setting for diff render style: the +/- fg-colored look is
 * hardcoded in renderDiff (modes/components/diff.ts) and reaches the edit
 * renderer through renderContext.renderDiff, which the edit renderer treats
 * as pluggable (`renderContext?.renderDiff ?? plainDiffRender`). This
 * extension reassigns editToolRenderer.renderResult - the same object the
 * TUI registers as toolRenderers.edit / toolRenderers.apply_patch - with a
 * wrapper that injects a rich renderer into that hook and post-processes the
 * framed rows so added/removed lines get a full-width background tint
 * (borders included), the same SGR-stabilization trick renderOutputBlock
 * uses for tool-state backgrounds.
 *
 * Differences from stock: added/removed lines are syntax-highlighted (stock
 * highlights context only), changed lines get a bg wash instead of green/red
 * foreground, 1:1 replacements mark the changed span with a brighter emph bg
 * instead of inverse video, and indentation guide dots are dropped (the bg
 * makes whitespace visible).
 *
 * Palette mirrors the cozybox delta theme (lib/theme.nix deltaTheme), so omp
 * edit diffs match `git diff` through delta. Dark/light is picked per render
 * via theme.isLight.
 *
 * Known limits: streaming/approval previews keep the stock style (that path
 * hardcodes the classic renderer); non-truecolor terminals and any renderer
 * failure fall back to the stock renderer.
 */
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
	editToolRenderer,
	getLanguageFromPath,
	highlightCode,
	renderDiff as classicRenderDiff,
	theme,
} from "@oh-my-pi/pi-coding-agent";

const TAB = "   "; // DEFAULT_TAB_WIDTH = 3 (pi-utils tab-spacing.ts)
const BG_RESET = "\x1b[49m";
const FG_RESET = "\x1b[39m";

const PALETTES = {
	dark: { add: "#1d2c1d", addEmph: "#2b4a2b", del: "#3c1f1e", delEmph: "#72261d" },
	light: { add: "#edf6ed", addEmph: "#d8ead8", del: "#fff0ed", delEmph: "#ffd7d1" },
} as const;

function bgAnsi(hex: string): string {
	const r = Number.parseInt(hex.slice(1, 3), 16);
	const g = Number.parseInt(hex.slice(3, 5), 16);
	const b = Number.parseInt(hex.slice(5, 7), 16);
	return `\x1b[48;2;${r};${g};${b}m`;
}

/** Every line-level bg this extension can emit; used to detect diff rows in framed output. */
const LINE_BGS = [
	bgAnsi(PALETTES.dark.add),
	bgAnsi(PALETTES.dark.del),
	bgAnsi(PALETTES.light.add),
	bgAnsi(PALETTES.light.del),
];

interface RenderDiffOptions {
	filePath?: string;
}

type RenderDiffFn = (diffText: string, options?: RenderDiffOptions) => string;

interface DiffRenderContext {
	renderDiff?: RenderDiffFn;
}

interface RenderOptionsLike {
	renderContext?: DiffRenderContext;
}

interface ComponentLike {
	render(width: number): readonly string[];
	invalidate?(): void;
}

type RenderResultFn = (result: unknown, options: RenderOptionsLike, uiTheme: unknown, args?: unknown) => ComponentLike;

type DiffPrefix = "+" | "-" | " ";

interface ParsedDiffLine {
	prefix: DiffPrefix;
	lineNum: string;
	content: string;
}

function replaceTabs(text: string): string {
	return text.replaceAll("\t", TAB);
}

/** Same formats the stock renderer accepts: "+123|content" (canonical), "+123 content" (legacy). */
function parseDiffLine(line: string): ParsedDiffLine | null {
	const canonical = line.match(/^([+\-\s])(\s*\d+)\|(.*)$/);
	if (canonical) {
		const marker = canonical[1] ?? " ";
		const prefix: DiffPrefix = marker === "+" || marker === "-" ? marker : " ";
		return { prefix, lineNum: canonical[2] ?? "", content: canonical[3] ?? "" };
	}
	const legacy = line.match(/^([+\-\s])(?:(\s*\d+)\s)?(.*)$/);
	if (!legacy) return null;
	const marker = legacy[1] ?? " ";
	const prefix: DiffPrefix = marker === "+" || marker === "-" ? marker : " ";
	return { prefix, lineNum: legacy[2] ?? "", content: legacy[3] ?? "" };
}

/**
 * Batch syntax highlighting. Each contiguous run of diff lines is split into
 * an old-side view (context + removed) and a new-side view (context + added)
 * and highlighted as one block, so changed lines tokenize with real
 * surrounding context - the same "hunk as two file views" approach
 * diffs.nvim uses. Returns highlighted content per line index.
 */
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
				// Context lines were already assigned from the new-side view.
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

/** Longest common prefix/suffix span between two raw lines; null when identical. */
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

/**
 * Overlay a brighter emph background over visible columns [from, to) of an
 * ANSI-highlighted line, restoring the line background afterwards. Column
 * positions come from the raw text, which highlightCode preserves 1:1.
 */
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
	// Reserve 3 gutter digits, mirroring the stock renderer's streaming-stable gutter.
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

const richRenderDiff: RenderDiffFn = (diffText, options) => {
	try {
		if (theme.getColorMode() !== "truecolor") return classicRenderDiff(diffText, options);
		return renderRich(diffText, options?.filePath);
	} catch {
		return classicRenderDiff(diffText, options);
	}
};

/**
 * Extend a diff line's background across the framed row's interior (gutter
 * and padding included), stopping short of the frame's outer border glyphs.
 * The border cells keep the default background: ghostty's
 * window-padding-color=extend paints window padding with the edge cells'
 * background, so a tinted border cell would bleed outside the box. Mirrors
 * renderOutputBlock's own bg stabilization: every bg reset inside the span
 * immediately re-opens the line bg.
 */
function extendRowBg(row: string): string {
	let lineBg: string | undefined;
	for (const candidate of LINE_BGS) {
		if (row.includes(candidate)) {
			lineBg = candidate;
			break;
		}
	}
	if (!lineBg) return row;
	const bg = lineBg;
	// First `│` is the frame's left border (it precedes the gutter separator);
	// last `│` is the right border (nothing printable follows it).
	const vertical = theme.boxRound?.vertical ?? "│";
	const first = row.indexOf(vertical);
	const last = row.lastIndexOf(vertical);
	if (first === -1 || last <= first) return row;
	const head = row.slice(0, first + vertical.length);
	const mid = row.slice(first + vertical.length, last);
	const tail = row.slice(last);
	const stabilized = mid.replaceAll(BG_RESET, `${BG_RESET}${bg}`).replace(/\x1b\[0?m/g, match => `${match}${bg}`);
	return `${head}${bg}${stabilized}${BG_RESET}${tail}`;
}

function wrapComponent(component: ComponentLike): ComponentLike {
	if (typeof component?.render !== "function") return component;
	const originalRender = component.render.bind(component);
	let memoIn: readonly string[] | undefined;
	let memoOut: readonly string[] | undefined;
	component.render = (width: number): readonly string[] => {
		const rows = originalRender(width);
		if (rows === memoIn && memoOut) return memoOut;
		let changed = false;
		const out = rows.map(row => {
			const extended = extendRowBg(row);
			if (extended !== row) changed = true;
			return extended;
		});
		memoIn = rows;
		memoOut = changed ? out : rows;
		return memoOut;
	};
	return component;
}

export default function richDiffExtension(pi: ExtensionAPI) {
	try {
		// editToolRenderer is the exact object registered as toolRenderers.edit /
		// toolRenderers.apply_patch; reassigning its method redirects the TUI.
		const renderer = editToolRenderer as unknown as { renderResult: RenderResultFn };
		const original = renderer.renderResult.bind(editToolRenderer);
		renderer.renderResult = (result, options, uiTheme, args) => {
			try {
				const ctx = options?.renderContext;
				if (ctx && typeof ctx === "object") ctx.renderDiff = richRenderDiff;
			} catch {
				// keep stock renderer for this render
			}
			return wrapComponent(original(result, options, uiTheme, args));
		};
	} catch (err) {
		pi.logger.warn("rich-diff: failed to install, keeping stock diff rendering", { error: String(err) });
	}
}
