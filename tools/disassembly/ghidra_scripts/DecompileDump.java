// Ghidra headless post-script.
// args: <outDir> [<funcNamePrefix> ...]   또는   <outDir> --all
// @category Analysis
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

public class DecompileDump extends GhidraScript {

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length < 1) {
			println("DecompileDump: 출력 디렉토리 인자가 필요합니다.");
			return;
		}

		File outDir = new File(args[0]);
		if (!outDir.exists()) {
			outDir.mkdirs();
		}

		boolean all = false;
		List<String> prefixes = new ArrayList<>();
		for (int i = 1; i < args.length; i++) {
			if ("--all".equals(args[i])) {
				all = true;
			} else if (args[i] != null && !args[i].isEmpty()) {
				prefixes.add(args[i]);
			}
		}

		DecompInterface decomp = new DecompInterface();
		decomp.openProgram(currentProgram);

		FunctionManager fm = currentProgram.getFunctionManager();
		PrintWriter index = new PrintWriter(new FileWriter(new File(outDir, "_index.txt")));

		int total = 0;
		int done = 0;
		int failed = 0;

		for (Function f : fm.getFunctions(true)) {
			if (monitor.isCancelled()) {
				break;
			}
			String name = f.getName(true);

			if (!all && !matchesPrefix(name, prefixes)) {
				continue;
			}
			if (f.isThunk() || f.isExternal()) {
				continue;
			}
			total++;

			try {
				DecompileResults res = decomp.decompileFunction(f, 60, monitor);
				if (res != null && res.decompileCompleted() && res.getDecompiledFunction() != null) {
					String code = res.getDecompiledFunction().getC();
					String safe = sanitize(name);
					File out = new File(outDir, safe + ".c");
					try (PrintWriter pw = new PrintWriter(new FileWriter(out))) {
						pw.println("// function : " + name);
						pw.println("// address  : " + f.getEntryPoint());
						pw.println("// signature: " + f.getSignature());
						pw.println();
						pw.println(code);
					}
					index.println(name + "\t" + safe + ".c\t" + f.getEntryPoint());
					done++;
				} else {
					index.println(name + "\t<decompile-failed>\t" + f.getEntryPoint());
					failed++;
				}
			} catch (Exception e) {
				index.println(name + "\t<error: " + e.getMessage() + ">\t" + f.getEntryPoint());
				failed++;
			}
		}

		index.flush();
		index.close();
		decomp.dispose();

		println("DecompileDump: 대상 " + total + " / 성공 " + done + " / 실패 " + failed);
	}

	private boolean matchesPrefix(String name, List<String> prefixes) {
		for (String p : prefixes) {
			if (name.startsWith(p)) {
				return true;
			}
		}
		return false;
	}

	private String sanitize(String name) {
		String s = name.replaceAll("[^A-Za-z0-9._-]", "_");
		if (s.length() > 180) {
			s = s.substring(0, 180);
		}
		return s;
	}
}
