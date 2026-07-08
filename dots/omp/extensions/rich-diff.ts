/**
 * rich-diff: lazy loader for the diffs.nvim-style edit diff renderer.
 *
 * The actual implementation lives in rich-diff-host.ts, which value-imports
 * the host package (@oh-my-pi/pi-coding-agent). Evaluating that import inside
 * loadExtensions triggers omp's bundled-registry cascade - every bundled pi-*
 * package surface gets evaluated to serve it - and costs ~850ms of every
 * startup (measured with PI_TIMING; without it loadExtensions is ~20ms).
 *
 * Deferral has to thread a needle: runtime dynamic imports from extension
 * modules never reach omp's Bun plugins (bare specifiers, the rewritten
 * omp-legacy-pi-bundled: scheme, and extension-registered onResolve hooks all
 * fail to resolve post-load). The one sanctioned path is a *relative* import
 * of a sibling source file: omp's extension-graph onLoad hook is permanent,
 * covers relative dynamic-import literals, and re-reads + rewrites the file
 * at import time. So the sibling loads on session_start with working host
 * imports, and the cascade runs after the TUI is up. Until then (and in the
 * scrollback of resumed sessions) edit diffs render with the stock style.
 *
 * rich-diff-host.ts is deliberately not symlinked into ~/.omp/agent/extensions
 * (see modules/users/user-config/activation.nix): discovery would load it
 * eagerly as its own extension and put the cascade right back into startup.
 */
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

export default function richDiffExtension(pi: ExtensionAPI) {
	let installing = false;
	pi.on("session_start", async () => {
		if (installing) return;
		installing = true;
		try {
			// Relative dynamic import by design (ts-no-dynamic-import exception):
			// a static import would evaluate the host package during loadExtensions;
			// this routes through omp's extension-graph hook at runtime instead.
			const host = await import("./rich-diff-host.ts");
			host.install();
		} catch (err) {
			installing = false;
			pi.logger.warn("rich-diff: failed to install, keeping stock diff rendering", { error: String(err) });
		}
	});
}
