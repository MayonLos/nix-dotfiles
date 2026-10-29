local capture = assert(_G.MayonSelfcheck)
-- Real RPC stderr is arbitrarily chunked. Severity belongs to reassembled
-- server lines, not each serialized libuv chunk.
vim.lsp.log.error("rpc", "nixd", "stderr", "I")
assert(#capture.finish() == 0, "interim report classified an unfinished stderr prefix")
vim.lsp.log.error("rpc", "nixd", "stderr", "[")
vim.lsp.log.error("rpc", "nixd", "stderr", "12:00:00.000] 42: --> notify textDocument/")
vim.lsp.log.error("rpc", "nixd", "stderr", "publishDiagnostics\n")
vim.lsp.log.error("rpc", "marksman", "stderr", "[12:00:00 INF] <LSP Entry> local fixture\n")
vim.lsp.log.error(
	"rpc",
	"clangd",
	"stderr",
	"I[12:00:00.000] ASTWorker building file with command\n[/fixture]\n/nix/store/fixture/bin/clang fixture.c\n"
)
assert(#capture.finish() == 0, "INFO stderr fragments were misclassified: " .. vim.inspect(capture.events))
assert(#capture.lsp_observations == 5, "server lines were not reconstructed")
print("LSP stderr chunk reconstruction passed")
