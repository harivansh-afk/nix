/**
 * claude-purple: purple tool dots and loader on an otherwise-coral theme.
 *
 * The theme cannot express this split. Every built-in renderer draws its
 * header dot via theme.styledSymbol("tool.<name>", "accent"), the
 * search-family renderers (grep/glob/ast-grep/tool-discovery) draw theirs
 * via theme.fg(color, theme.symbol("icon.search")), and the working loader
 * paints its spinner with theme.fg("accent", frame) and its message crest
 * with DEFAULT_SHIMMER_PALETTE.high = "accent". That same "accent" token
 * also colors tool titles, header descriptions, and grep's per-file result
 * headers - so a purple accent bleeds purple over whole tool blocks.
 * cozybox keeps accent coral and this extension re-lands only the dot,
 * the spinner, and the shimmer crest on the claude-purple lane.
 *
 * Implementation notes:
 * - Patches the Theme prototype (via Object.getPrototypeOf(theme)), not the
 *   instance: theme reloads and dark/light auto-switching reassign the
 *   exported binding to a fresh instance sharing the same prototype.
 * - The bundled-registry shim snapshots `export const theme = ...` at module
 *   load, so the imported binding goes stale after a theme switch. All
 *   per-call state derives from `this`; the shimmer getter uses the last
 *   instance stamped by the prototype patches.
 * - The purple is read per call from getColorHex("statusLinePath") - the
 *   prompting-bar path shares the claude-purple lane in lib/theme.nix
 *   (#b1b9f9 dark, #5769f7 light) - so mode switches and future recolors
 *   stay in lockstep.
 * - The shimmer palette compiles its tiers once per (theme, palette) into a
 *   symbol-keyed cache on the palette object; the own-symbol sweep busts any
 *   compile that happened before install.
 *
 * Known limits: non-truecolor terminals keep stock accent colors.
 */
import { theme } from "@oh-my-pi/pi-coding-agent";
import { DEFAULT_SHIMMER_PALETTE } from "@oh-my-pi/pi-coding-agent/modes/theme/shimmer";

const FG_RESET = "\x1b[39m";

interface ThemeLike {
	styledSymbol(key: string, color: string): string;
	symbol(key: string): string;
	fg(color: string, text: string): string;
	getColorHex(color: string): string;
	getColorMode(): string;
	spinnerFrames: string[];
}

function fgAnsi(hex: string): string {
	const r = Number.parseInt(hex.slice(1, 3), 16);
	const g = Number.parseInt(hex.slice(3, 5), 16);
	const b = Number.parseInt(hex.slice(5, 7), 16);
	return `\x1b[38;2;${r};${g};${b}m`;
}

function purpleFg(self: ThemeLike): string | undefined {
	if (self.getColorMode() !== "truecolor") return undefined;
	const hex = self.getColorHex("statusLinePath");
	return /^#[0-9a-fA-F]{6}$/.test(hex) ? fgAnsi(hex) : undefined;
}

let installed = false;

export function install(): void {
	if (installed) return;
	installed = true;

	const proto = Object.getPrototypeOf(theme) as ThemeLike;
	const originalStyledSymbol = proto.styledSymbol;
	const originalSymbol = proto.symbol;
	const originalFg = proto.fg;
	let lastTheme: ThemeLike = theme as unknown as ThemeLike;

	proto.styledSymbol = function (this: ThemeLike, key: string, color: string): string {
		lastTheme = this;
		if (key.startsWith("tool.")) {
			const fg = purpleFg(this);
			if (fg) return `${fg}${originalSymbol.call(this, key)}${FG_RESET}`;
		}
		return originalStyledSymbol.call(this, key, color);
	};

	proto.symbol = function (this: ThemeLike, key: string): string {
		lastTheme = this;
		const raw = originalSymbol.call(this, key);
		if (key === "icon.search") {
			const fg = purpleFg(this);
			if (fg) return `${fg}${raw}${FG_RESET}`;
		}
		return raw;
	};

	proto.fg = function (this: ThemeLike, color: string, text: string): string {
		lastTheme = this;
		if (color === "accent" && text.length <= 2 && this.spinnerFrames?.includes(text)) {
			const fg = purpleFg(this);
			if (fg) return `${fg}${text}${FG_RESET}`;
		}
		return originalFg.call(this, color, text);
	};

	const palette = DEFAULT_SHIMMER_PALETTE as Record<string | symbol, unknown>;
	for (const sym of Object.getOwnPropertySymbols(palette)) {
		delete palette[sym];
	}
	Object.defineProperty(DEFAULT_SHIMMER_PALETTE, "high", {
		configurable: true,
		enumerable: true,
		get(): string | { ansi: string } {
			const fg = purpleFg(lastTheme);
			return fg ? { ansi: fg } : "accent";
		},
	});
}
