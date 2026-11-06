# filesystem pack

Keeps tool calls to the MCP reference filesystem server inside configured directories, with reads and writes configured separately. Applies when `server.name` is `filesystem`, or an alias for it.

Verified against: [`@modelcontextprotocol/server-filesystem`](https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem) 2.2.0, from `src/filesystem/README.md` at [modelcontextprotocol/servers tag v2.3.0](https://github.com/modelcontextprotocol/servers/tree/v2.3.0/src/filesystem).

## Read this first: this pack covers tool calls only

The server also exposes files as MCP resources, so a client can read any file inside the server's allowed directories with `resources/read`, without making a tool call. This pack cannot see those requests. If your paths must hold for every access, your integration has to block or separately authorize `resources/read` for this server.

## Tools

| Tool | Access required | Path arguments |
|---|---|---|
| `read_text_file`, `read_file` (deprecated alias), `read_media_file` | read | `path` |
| `read_multiple_files` | read, for every entry | `paths` |
| `list_directory`, `list_directory_with_sizes`, `directory_tree`, `get_file_info` | read | `path` |
| `search_files` | read, and `pattern` must have no traversal | `path` |
| `write_file`, `append_file`, `edit_file` (even with `dryRun`), `create_directory` | write | `path` |
| `move_file` | write on both | `source`, `destination` |
| `copy_file` | read on source, write on destination | `source`, `destination` |
| `list_allowed_directories` | allowed once any `read_paths` are configured | none |

Any other tool is denied. Write access does not imply read access, so a directory that needs both must be in both lists.

## Deny codes

| Code | Denies when |
|---|---|
| `filesystem.tool_not_supported` | the tool is not in the table above |
| `filesystem.missing_argument` | a required argument is missing or has the wrong type, or `paths` is empty |
| `filesystem.path_not_absolute` | a path is relative, starts with `~` or is empty |
| `filesystem.path_traversal` | a path has a `..` segment, a backslash or an encoded dot or separator (`%2e`, `%2f`, `%5c`), or a search pattern has traversal |
| `filesystem.invalid_path` | a path has control characters, or reaches a kernel link such as `/proc/self/root` or `/dev/fd` |
| `filesystem.path_not_allowed` | a safe path is outside the configured read or write paths |
| `filesystem.path_denied` | a path matches `deny_globs` |

## Configuration

Config lives under `data.mcp_config.filesystem`. With no config, every path is denied.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `read_paths` | list of absolute paths | none | Directories that read tools may touch |
| `write_paths` | list of absolute paths | none | Directories that write tools may touch |
| `deny_globs` | list of globs | none | Paths refused even inside allowed directories. Matched case-insensitively. |
| `require_approval_for_writes` | boolean | `false` | Hold every write for human approval |

Directories match on whole segments, so `/srv/app` covers `/srv/app/a` and not `/srv/app-secrets`. Paths are compared as written, so `/SRV/app` does not match `/srv/app`; on a case-insensitive filesystem this errs toward refusing.

The server marks `write_file`, `edit_file` and `move_file` as destructive, so they also need an entry in the baseline pack's `destructive_allowlist`.

## Limitations

- **Symlinks and hard links are invisible.** Rego sees a string and cannot look at the disk. `/srv/app/link` is allowed by `/srv/app` even if that link points to `/etc`. The server resolves symlinks against its own allowed directories, so start it with the same directories, and do not treat this pack as a replacement for that check. The server's README notes that hard links can reach content outside its allowed directories as well.
- **POSIX paths only.** Backslashes are refused, so Windows paths are denied.
- **Listings reveal names.** `deny_globs` are checked against the paths in the arguments. Listing or searching an allowed parent directory can still show the name of a denied file, though not its content.
- **Start the server read-only if you can.** `--read-only` removes write tools at the server, which is stronger than any policy here.
