# Collaboration Guide

## Branch Strategy

- `main`: always kept in a working state
- `feature/<name>`: new features
- `fix/<name>`: bug fixes
- `docs/<name>`: documentation updates

Examples:

- `feature/login-ui`
- `feature/map-home`
- `feature/auth-service`

## Basic Workflow

1. Pull the latest `main`
2. Create your own branch
3. Implement one feature or fix
4. Test locally
5. Open a Pull Request
6. Merge after review

## Recommended Role Split

### 1. Login and Auth

- `lib/pages/login_page.dart`
- `lib/services/auth_service.dart`

### 2. Home and Map

- `lib/pages/map_home_page.dart`

### 3. App Flow and Navigation

- `lib/main.dart`
- `lib/pages/app_entry_page.dart`

### 4. Assets and UI Polish

- `assets/`

### 5. Testing and QA

- `test/`

## Commit Message Rules

Use short conventional-style messages:

- `feat: add login page validation`
- `fix: resolve map marker issue`
- `docs: update collaboration guide`

## Pull Request Rules

- One PR should contain one main purpose
- Include what changed and how it was tested
- Do not push directly to `main`
- Ask for at least one teammate review before merging

## Conflict Prevention Tips

- Avoid editing the same file at the same time
- Assign a clear owner for shared files like `main.dart`
- Agree on folder structure and naming before large changes
- Merge small PRs often instead of keeping long-lived branches
