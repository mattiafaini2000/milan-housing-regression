# Read --name value pairs used by the analysis entry points.
parse_arguments <- function(args, defaults, required = character()) {
  if (length(args) %% 2L != 0L) stop("Each option needs a value.")
  options <- defaults
  seen <- character()
  indices <- if (length(args)) seq.int(1L, length(args), by = 2L) else integer()
  for (index in indices) {
    name <- sub("^--", "", args[index])
    if (!startsWith(args[index], "--") || !name %in% names(defaults)) {
      stop("Unknown option: ", args[index])
    }
    if (name %in% seen) stop("Repeated option: --", name)
    options[[name]] <- args[index + 1L]
    seen <- c(seen, name)
  }
  for (name in required) {
    if (is.null(options[[name]]) || !nzchar(options[[name]])) {
      stop("Required option: --", name)
    }
  }
  options
}

# Inputs may be read from an explicitly supplied external data directory.
input_file <- function(project_root, input_root, relative_path) {
  if (grepl("^([A-Za-z]:|[/\\\\])", relative_path)) {
    stop("Input filenames must be relative to --input-root.")
  }
  root <- if (grepl("^([A-Za-z]:|[/\\\\])", input_root)) input_root else file.path(project_root, input_root)
  normalizePath(file.path(root, relative_path), winslash = "/", mustWork = TRUE)
}

# Reject traversal and symlink escapes before creating an output directory.
project_output_path <- function(project_root, relative_path, create_parent = TRUE) {
  if (!nzchar(relative_path) || grepl("^([A-Za-z]:|[/\\\\])", relative_path)) {
    stop("Output paths must be relative to the project.")
  }
  parts <- strsplit(gsub("\\\\", "/", relative_path), "/", fixed = TRUE)[[1L]]
  if (any(parts %in% c("", ".", ".."))) stop("Invalid output path.")
  root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)
  candidate <- root
  for (part in parts) {
    candidate <- file.path(candidate, part)
    if (file.exists(candidate) || dir.exists(candidate)) {
      resolved <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
      if (!startsWith(tolower(resolved), paste0(tolower(root), "/"))) {
        stop("Output path leaves the project.")
      }
    }
  }
  if (create_parent) dir.create(dirname(candidate), recursive = TRUE, showWarnings = FALSE)
  candidate
}
