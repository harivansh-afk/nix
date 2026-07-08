const TAB = "   ";
export const BG_RESET = "\x1b[49m";
export const FG_RESET = "\x1b[39m";

export const PALETTES = {
	dark: { add: "#1d2c1d", addEmph: "#2b4a2b", del: "#3c1f1e", delEmph: "#72261d" },
	light: { add: "#edf6ed", addEmph: "#d8ead8", del: "#fff0ed", delEmph: "#ffd7d1" },
} as const;

export function bgAnsi(hex: string): string {
	const r = Number.parseInt(hex.slice(1, 3), 16);
	const g = Number.parseInt(hex.slice(3, 5), 16);
	const b = Number.parseInt(hex.slice(5, 7), 16);
	return `\x1b[48;2;${r};${g};${b}m`;
}

export const LINE_BGS = [
	bgAnsi(PALETTES.dark.add),
	bgAnsi(PALETTES.dark.del),
	bgAnsi(PALETTES.light.add),
	bgAnsi(PALETTES.light.del),
];

export interface RenderDiffOptions {
	filePath?: string;
}

export type RenderDiffFn = (diffText: string, options?: RenderDiffOptions) => string;

export interface DiffRenderContext {
	renderDiff?: RenderDiffFn;
}

export interface RenderOptionsLike {
	renderContext?: DiffRenderContext;
}

export interface ComponentLike {
	render(width: number): readonly string[];
	invalidate?(): void;
}

export type RenderResultFn = (result: unknown, options: RenderOptionsLike, uiTheme: unknown, args?: unknown) => ComponentLike;

export type DiffPrefix = "+" | "-" | " ";

export interface ParsedDiffLine {
	prefix: DiffPrefix;
	lineNum: string;
	content: string;
}

export function replaceTabs(text: string): string {
	return text.replaceAll("\t", TAB);
}

// Accepted line formats: "+123|content" (canonical) and "+123 content" (legacy).
export function parseDiffLine(line: string): ParsedDiffLine | null {
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
