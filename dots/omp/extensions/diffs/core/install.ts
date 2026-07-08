import { editToolRenderer, theme } from "@oh-my-pi/pi-coding-agent";
import { BG_RESET, type ComponentLike, LINE_BGS, type RenderResultFn } from "./diff.ts";
import { richRenderDiff } from "./render.ts";

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

interface EditToolRendererLike {
	renderResult: RenderResultFn;
}

let installed = false;

// editToolRenderer is the live object registered as toolRenderers.edit / toolRenderers.apply_patch; reassigning its method redirects the TUI.
export function install(): void {
	if (installed) return;
	installed = true;
	const candidate: unknown = editToolRenderer;
	if (!candidate || typeof candidate !== "object" || !("renderResult" in candidate) || typeof candidate.renderResult !== "function") {
		throw new Error("editToolRenderer.renderResult missing");
	}
	const renderer = candidate as EditToolRendererLike;
	const original = renderer.renderResult.bind(renderer);
	renderer.renderResult = (result, options, uiTheme, args) => {
		try {
			const ctx = options?.renderContext;
			if (ctx && typeof ctx === "object") ctx.renderDiff = richRenderDiff;
		} catch {}
		return wrapComponent(original(result, options, uiTheme, args));
	};
}
