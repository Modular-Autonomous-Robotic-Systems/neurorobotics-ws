#!/usr/bin/env python3
"""
Script Name: parse_branch_commits.py

Description:
    This Python script:
      1. Clones or opens a local Git repository using GitPython.
      2. Checks out a specified branch.
      3. Retrieves the last N commits.
      4. Parses each commit's Problem, Solution, and Note sections.
      5. Handles multi-line bullet points:
         - Lines beginning with numeric label ("[0-9]+.") => new bullet
         - Lines beginning with three spaces ("   ") => continuation of the previous bullet
      6. Combines and enumerates them into a markdown changelog.

Usage:
    python parse_branch_commits.py --count 5
        => Will parse the last 5 commits from the default configured branch,
           and produce a file "changelog_<timestamp>.log"

References:
    - GitPython: https://gitpython.readthedocs.io/en/stable/
    - Example usage of iter_commits: https://stackoverflow.com/questions/37443462
    - Regex details: https://docs.python.org/3/howto/regex.html
"""

import os
import re
import argparse
from git import Repo
from datetime import datetime

# -----------------------------------------------------------------------------
# User Configuration Defaults
# -----------------------------------------------------------------------------
SSH_REPO_URL = "git@github.com:Modular-Autonomous-Robotic-Systems/neurorobotics-ws.git"
BRANCH_NAME = "shreyas/SITL_and_dep_updates"  # The branch from which to gather commits
LOCAL_REPO_PATH = "/ws"

# -----------------------------------------------------------------------------
# Internal Helpers
# -----------------------------------------------------------------------------

def extract_section_lines(commit_message, section_name):
    """
    Extract the lines belonging to a section (e.g., "Problem", "Solution", "Note")
    from a commit message.

    Returns a list of lines within the specified section without any post-processing yet.
    """
    pattern = rf"{section_name}\s*[\r\n]+[=]+[\r\n]+(.*?)(?=(?:Problem|Solution|Note|$))"
    matches = re.search(pattern, commit_message, re.IGNORECASE | re.DOTALL)
    if not matches:
        return []

    section_text = matches.group(1).strip()
    lines = section_text.splitlines()
    return lines

def combine_multiline_bullets(lines):
    """
    Given a list of raw lines from a section, this function:
      - Detects if a line starts with '[0-9]+[.)]' => a new bullet
      - Detects if a line starts with three spaces ('   ') => continuation of the previous bullet
      - Otherwise => a new bullet

    Returns a list of bullet strings, each potentially spanning multiple lines if there
    was a continuation.
    """
    bullet_points = []
    current_bullet = ""

    bullet_pattern = re.compile(r"^[0-9]+[\.\)]\s*")

    for line in lines:
        # Check for three consecutive spaces at the start => continuation
        if line.startswith("   "):
            if not current_bullet:
                current_bullet = line.strip()
            else:
                current_bullet += " " + line.strip()
        else:
            # Potential new bullet if it matches the numeric label
            if bullet_pattern.match(line):
                # If we have an existing bullet, push it to the list
                if current_bullet:
                    bullet_points.append(current_bullet)
                # Remove the bullet numbering from the new line
                cleaned_line = bullet_pattern.sub("", line, count=1).strip()
                current_bullet = cleaned_line
            else:
                # If it doesn't match the bullet pattern nor 3 spaces,
                # treat it as a brand new bullet
                if current_bullet:
                    bullet_points.append(current_bullet)
                current_bullet = line.strip()

    if current_bullet:
        bullet_points.append(current_bullet)

    return bullet_points

def parse_commit_message_for_sections(commit_message):
    """
    Parse a commit message into Problems, Solutions, and Notes, applying
    multi-line bullet logic.
    """
    raw_problems = extract_section_lines(commit_message, "Problem")
    raw_solutions = extract_section_lines(commit_message, "Solution")
    raw_notes = extract_section_lines(commit_message, "Note")

    problems = combine_multiline_bullets(raw_problems)
    solutions = combine_multiline_bullets(raw_solutions)
    notes = combine_multiline_bullets(raw_notes)

    return problems, solutions, notes

def format_markdown_changelog(problems, solutions, notes):
    """
    Generate a markdown document with enumerated lists under
    Problems, Solutions, and Notes.
    """
    md_output = []
    md_output.append("# Pull Request Changelog\n")

    # Problems Section
    md_output.append("## Problems")
    for i, line in enumerate(problems, start=1):
        md_output.append(f"{i}. {line}")

    # Solutions Section
    md_output.append("\n## Solutions")
    for i, line in enumerate(solutions, start=1):
        md_output.append(f"{i}. {line}")

    # Notes Section
    md_output.append("\n## Notes")
    for i, line in enumerate(notes, start=1):
        md_output.append(f"{i}. {line}")

    return "\n".join(md_output)

def get_branch_commits(repo_path, ssh_url, branch_name, last_n):
    """
    Clone or open the repository at 'repo_path'.
    Fetch the latest commits for 'branch_name'.
    Return only the last 'last_n' commits from that branch (newest first).
    """
    if not os.path.exists(repo_path):
        print(f"Cloning repository from {ssh_url} into {repo_path} ...")
        repo = Repo.clone_from(ssh_url, repo_path)
    else:
        print(f"Opening existing repository at {repo_path} ...")
        repo = Repo(repo_path)

    print(f"Fetching branch '{branch_name}'...")
    repo.remotes.origin.fetch(branch_name)

    if branch_name in repo.heads:
        target_branch = repo.heads[branch_name]
    else:
        target_branch = repo.create_head(branch_name, f"origin/{branch_name}")

    repo.head.reference = target_branch
    repo.head.reset(index=True, working_tree=True)

    commits = list(repo.iter_commits(target_branch, max_count=last_n))
    commits.reverse()

    return commits

def main():
    parser = argparse.ArgumentParser(
        description="Parse the last N commits from a branch to build a changelog with Problem, Solution, and Note sections, supporting multiline bullet points."
    )
    parser.add_argument("--count", type=int, default=5, help="Number of recent commits to parse.")
    parser.add_argument("--branch", type=str, default=BRANCH_NAME, help="The branch to parse commits from.")
    parser.add_argument("--repo-url", type=str, default=SSH_REPO_URL, help="SSH/HTTPS URL of the GitHub repository.")
    parser.add_argument("--local-path", type=str, default=LOCAL_REPO_PATH, help="Local path to clone/open the repository.")
    args = parser.parse_args()

    commits = get_branch_commits(args.local_path, args.repo_url, args.branch, args.count)

    all_problems = []
    all_solutions = []
    all_notes = []

    for commit in commits:
        problems, solutions, notes = parse_commit_message_for_sections(commit.message)
        all_problems.extend(problems)
        all_solutions.extend(solutions)
        all_notes.extend(notes)

    md_changelog = format_markdown_changelog(all_problems, all_solutions, all_notes)

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    output_filename = f"changelog_{timestamp}.log"
    output_filepath = os.path.join(os.getcwd(), output_filename)

    with open(output_filepath, "w", encoding="utf-8") as f:
        f.write(md_changelog)

    print(f"Changelog successfully written to: {output_filepath}")

if __name__ == "__main__":
    main()
