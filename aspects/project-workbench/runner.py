#!/usr/bin/env python3
"""Launch an explicitly configured project in Kitty or an existing workspace tool."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import NoReturn


VIEWS = ("terminal", "editor", "files", "workspace")


def fail(message: str, status: int = 2) -> NoReturn:
    print(f"workspace-project: {message}", file=sys.stderr)
    raise SystemExit(status)


def parse_args(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    parser = argparse.ArgumentParser(prog="workspace-project")
    parser.add_argument("--projects-json", required=True)
    parser.add_argument("--kitty", required=True)
    parser.add_argument("--tmuxp", required=True)
    options, command = parser.parse_known_args(argv)
    if command and command[0] == "--":
        command = command[1:]
    return options, command


def load_projects(path: str) -> dict[str, dict[str, str]]:
    try:
        with open(path, encoding="utf-8") as source:
            projects = json.load(source)
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read project registry: {error}")
    if not isinstance(projects, dict):
        fail("project registry must be an object")
    return projects


def executable(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        fail(f"required command '{name}' is unavailable in PATH")
    return path


def direnv_prefix(directory: str, command: list[str], required: bool) -> list[str]:
    if not (Path(directory) / ".envrc").is_file():
        return command
    direnv = shutil.which("direnv")
    if direnv is None:
        if required:
            fail("this project has .envrc but 'direnv' is unavailable; refusing to bypass it")
        return command
    return [direnv, "exec", directory, *command]


def launch(
    projects: dict[str, dict[str, str]],
    kitty: str,
    tmuxp: str,
    command: list[str],
) -> NoReturn:
    if not command:
        fail("usage: workspace-project list | PROJECT [terminal|editor|files|workspace] [-- ARG ...]")
    if command == ["list"]:
        for project_id, project in projects.items():
            print(f"{project_id}\t{project['label']}")
        raise SystemExit(0)

    project_id = command[0]
    project = projects.get(project_id)
    if project is None:
        fail(f"unknown project '{project_id}'; run 'workspace-project list'")
    directory = project.get("directory")
    if not isinstance(directory, str) or not os.path.isabs(directory):
        fail(f"project '{project_id}' has no valid absolute directory")
    if not os.path.isdir(directory):
        fail(f"project directory does not exist or is not a directory: {directory}")
    os.chdir(directory)

    rest = command[1:]
    view = "terminal"
    if rest and rest[0] in VIEWS:
        view, rest = rest[0], rest[1:]
    if rest:
        if rest[0] != "--":
            fail("extra arguments must follow '--'")
        extra = rest[1:]
    else:
        extra = []

    if view == "terminal":
        if extra:
            fail("terminal view does not accept command arguments")
        # Kitty starts its configured interactive shell in this directory. Its
        # existing direnv hook decides whether the project's .envrc is trusted.
        os.execvpe(kitty, [kitty, "--directory", directory], os.environ.copy())

    if view == "workspace":
        if extra:
            fail("workspace view does not accept command arguments")
        if project.get("workspace") is not True:
            fail(f"project '{project_id}' has no workspace enabled")
        config = project.get("tmuxp_config")
        if not isinstance(config, str) or not os.path.isabs(config):
            fail(f"project '{project_id}' has no valid tmuxp configuration")
        tmuxp = executable(tmuxp)
        # tmuxp load reuses an existing session with this configured session_name;
        # it attaches without duplicating windows or panes.
        child = [kitty, "--directory", directory, tmuxp, "load", "-y", config]
        child = direnv_prefix(directory, child, required=True)
        os.execvpe(child[0], child, os.environ.copy())

    if view == "editor":
        editor = executable("workspace-editor")
        child = [kitty, "--directory", directory, editor, *(extra or ["."])]
    else:
        files = executable("workspace-files")
        child = [files, directory, *extra]

    # direnv exec rejects untrusted .envrc files itself. A rejection exits here;
    # the launcher never retries without direnv or switches to another directory.
    child = direnv_prefix(directory, child, required=True)
    os.execvpe(child[0], child, os.environ.copy())


def main(argv: list[str] | None = None) -> NoReturn:
    options, command = parse_args(sys.argv[1:] if argv is None else argv)
    projects = load_projects(options.projects_json)
    try:
        launch(projects, options.kitty, options.tmuxp, command)
    except OSError as error:
        fail(f"cannot launch project: {error}")


if __name__ == "__main__":
    main()
