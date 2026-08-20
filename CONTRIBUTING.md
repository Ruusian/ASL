# Contributing to ASL

Thank you for your interest in improving Android Subsystem for Linux (ASL)! This guide explains how to contribute.

---

## 🎯 Ways to Contribute

### 1. **Report Bugs** 🐛
Found an issue? Help us fix it:

- **GitHub Issues**: https://github.com/Ruusian/ASL/issues
- **Include**: Your device info, Android version, steps to reproduce
- **Example**:
  ```
  Title: Chroot fails to start on Samsung S21
  Device: Samsung Galaxy S21 (Android 14)
  Termux: v0.118
  Steps:
  1. Run: asl start
  2. See error: "Mount failed"
  3. Output: [paste asl doctor]
  ```

### 2. **Suggest Features** 💡
Have an idea? Share it:

- Open a GitHub Discussion or Issue with tag `[FEATURE]`
- Describe the use case and expected behavior
- Example: "Add support for automatic Wine prefix creation"

### 3. **Improve Documentation** 📚
Documentation helps everyone:

- Fix typos or unclear sections
- Add examples to TROUBLESHOOTING.md
- Expand GETTING_STARTED.md with new workflows
- Improve code comments

### 4. **Write Code** 💻
Contribute fixes and features:

- Fix bugs from [BUG_REPORT.md](BUG_REPORT.md)
- Implement features from GitHub Discussions
- Optimize performance-critical paths
- Add new shell subcommands

### 5. **Test & Validation** ✅
Help ensure quality:

- Test fixes on multiple Android devices
- Run test suite: See [TEST_RESULTS.md](TEST_RESULTS.md)
- Report compatibility issues
- Validate performance improvements

---

## 🚀 Getting Started

### Prerequisites

- GitHub account
- Git installed
- ASL development environment (cloned repo)
- Linux/Bash knowledge for code contributions

### Setup Development Environment

```bash
# 1. Fork the repository
# Go to: https://github.com/Ruusian/ASL
# Click "Fork" button

# 2. Clone your fork
git clone https://github.com/YOUR_USERNAME/ASL.git
cd ASL

# 3. Add upstream remote
git remote add upstream https://github.com/Ruusian/ASL.git

# 4. Create a feature branch
git checkout -b feature/my-awesome-feature
```

---

## 📝 Development Workflow

### Step 1: Create a Feature Branch

```bash
# Update main branch
git fetch upstream
git checkout master
git merge upstream/master

# Create feature branch
git checkout -b feature/your-feature-name
```

**Branch naming convention**:
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation
- `perf/` - Performance improvements
- `test/` - Test additions

### Step 2: Make Changes

**For shell scripts**:
```bash
# 1. Edit your target file
vim bin/asl  # or core/mount-chroot.sh, etc.

# 2. Test syntax
bash -n bin/asl

# 3. Run linting
shellcheck --severity=warning bin/asl

# 4. Test functionality
asl doctor
bash bin/asl help
```

**For documentation**:
- Use Markdown format
- Follow existing style (see README.md)
- Include code examples when helpful
- Link to related docs

### Step 3: Commit Changes

```bash
# Stage changes
git add core/mount-chroot.sh CHANGELOG.md

# Write descriptive commit message
git commit -m "Fix: Prevent race condition in mount-chroot.sh

- Add process existence check before unmounting
- Prevents zombie process cleanup failures
- Fixes issue #42

Tested on: Samsung S21, Pixel 6, OnePlus 9"
```

**Commit message format**:
```
Type: Summary (50 chars max)

- Detailed explanation (72 chars per line)
- Why the change was needed
- Any testing performed
- Fixes issue #123 (if applicable)
```

**Types**: `Fix`, `Feature`, `Docs`, `Perf`, `Test`, `Refactor`

### Step 4: Push & Create Pull Request

```bash
# Push to your fork
git push origin feature/your-feature-name

# Then go to GitHub and click "Create Pull Request"
```

**PR Template**:
```markdown
## Description
Brief explanation of what this PR does.

## Changes
- Change 1
- Change 2

## Testing
How you tested this change:
- Tested on Samsung S21
- Ran: asl doctor (output: ...)
- No regressions in...

## Related Issues
Fixes #123
Related to #124
```

---

## 🧪 Testing Your Changes

### Run Syntax Checks

```bash
# Check all shell scripts
for f in core/*.sh desktop/*.sh gaming/*.sh; do bash -n "$f" || echo "ERROR in $f"; done

# Run ShellCheck linting
shellcheck --severity=warning bin/asl core/*.sh
```

### Run Functional Tests

```bash
# System diagnostics
bash bin/asl doctor

# Help system
bash bin/asl help

# Show version
bash bin/asl --version
```

### Test on Device

If possible, test on an actual Android device:

```bash
# Copy to device
scp -r ASL termux@device:/home/termux/

# Test on device
asl doctor
asl overview
asl dashboard
```

---

## 📋 Code Style Guide

### Shell Script Style

1. **Use proper quoting**:
   ```bash
   # ✅ Good
   if [ -d "$DEBIANPATH" ]; then
       echo "Path: $DEBIANPATH"
   fi
   
   # ❌ Bad
   if [ -d $DEBIANPATH ]; then
       echo "Path: $DEBIANPATH"
   fi
   ```

2. **Error handling**:
   ```bash
   # ✅ Good
   if ! mount -v "$source" "$target"; then
       echo "[!] Mount failed"
       return 1
   fi
   
   # ❌ Bad
   mount -v "$source" "$target"  # No error check!
   ```

3. **Function documentation**:
   ```bash
   # Process manager function
   # Usage: process_manager <pid> <signal>
   # Returns: 0 on success, 1 on failure
   process_manager() {
       local pid=$1 signal=${2:-SIGTERM}
       # ...
   }
   ```

4. **Comments for logic**:
   ```bash
   # ✅ Good
   # Check if process exists before sending signal
   # to prevent PID recycling race condition
   if kill -0 "$pid" 2>/dev/null; then
       kill -"$signal" "$pid"
   fi
   
   # ❌ Bad
   kill -"$signal" "$pid"  # Just kill it
   ```

### Documentation Style

- Use **Markdown** format
- Include working code examples
- Add troubleshooting sections for docs
- Link to related documentation
- Update CHANGELOG.md with changes

---

## 🔍 Review Checklist

Before submitting a PR, check:

- [ ] **Syntax errors** - Run `bash -n` on all changed scripts
- [ ] **ShellCheck** - No warnings from `shellcheck`
- [ ] **Functionality** - Manually tested key features
- [ ] **Documentation** - README/TROUBLESHOOTING updated
- [ ] **Commit messages** - Clear and descriptive
- [ ] **No secrets** - No tokens, keys, or passwords in code
- [ ] **No breaking changes** - Backwards compatible
- [ ] **Tests pass** - All existing tests still work

---

## 📊 PR Review Process

1. **Your PR is created** → GitHub Actions runs tests
2. **Automated checks** → ShellCheck, syntax validation
3. **Code review** → Maintainers review changes
4. **Feedback** → Respond to review comments
5. **Approval** → PR is approved
6. **Merge** → Changes merged to master
7. **Release** → Changes included in next version

---

## 🐛 Bug Fix Process

If you're fixing a bug from [BUG_REPORT.md](BUG_REPORT.md):

1. **Reference the issue** in commit message:
   ```bash
   git commit -m "Fix: Prevent race condition in process_manager (Issue #2)"
   ```

2. **Include before/after code** in PR description

3. **Add test case** to verify fix works

4. **Update TEST_RESULTS.md** with test results

Example PR for Issue #2:
```markdown
## Description
Fixes race condition in process_manager where PID could be recycled 
between ps lookup and kill operation.

## Changes
- Add `kill -0` check before sending signals
- Prevents accidental termination of unrelated processes

## Testing
- Verified with: kill -0 99999 (returns 1)
- Tested asl ps on Samsung S21
- No regressions in existing process operations

Fixes #2
```

---

## 🎓 Learning Resources

**ASL Architecture**:
- [.instructions.md](.instructions.md) - Complete project context
- [CHANGELOG.md](CHANGELOG.md) - Version history & changes
- [BUG_REPORT.md](BUG_REPORT.md) - Known issues & analysis

**Bash Scripting**:
- [Bash Guide for Beginners](https://mywiki.wooledge.org/BashGuide)
- [ShellCheck](https://www.shellcheck.net/) - Script linting
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

**Git & GitHub**:
- [GitHub Flow Guide](https://guides.github.com/introduction/flow/)
- [How to Write Good Commit Messages](https://chris.beams.io/posts/git-commit/)

---

## 💬 Questions?

- **GitHub Discussions**: https://github.com/Ruusian/ASL/discussions
- **Issues**: https://github.com/Ruusian/ASL/issues
- **Email**: abhiksarkar00@gmail.com

---

**Thank you for contributing to ASL!** 🙏

Your contributions make ASL better for everyone. Whether it's code, docs, or testing — all contributions are valued!

---

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.
