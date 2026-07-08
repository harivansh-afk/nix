import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

// Deferred on purpose: a static host import evaluates omp's bundled registry inside loadExtensions (~850ms of every startup); the relative dynamic import is rewritten at runtime by omp's permanent extension-graph hook, and core/ must never be symlinked into ~/.omp/agent/extensions or discovery loads it eagerly.
export default function claudePurpleExtension(pi: ExtensionAPI) {
	let installing = false;
	pi.on("session_start", async () => {
		if (installing) return;
		installing = true;
		try {
			const host = await import("./core/install.ts");
			host.install();
		} catch (err) {
			installing = false;
			pi.logger.warn("claude-purple: failed to install, keeping theme accent colors", { error: String(err) });
		}
	});
}
