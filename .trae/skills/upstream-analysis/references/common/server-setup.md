# Server Setup & SSH Configuration

## SSH Key-Based Passwordless Login

### 1. Generate SSH Key (if not exists)

```bash
# Use ed25519 (recommended, no passphrase needed for automation)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

### 2. Copy Public Key to Server

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p <PORT> <USERNAME>@<SERVER_IP>
# Or manually:
cat ~/.ssh/id_ed25519.pub | ssh -p <PORT> <USERNAME>@<SERVER_IP> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

### 3. Configure SSH Alias

Edit `~/.ssh/config`:

```
Host <ALIAS>
    HostName <SERVER_IP>
    Port <PORT>
    User <USERNAME>
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

### 4. Test Connection

```bash
ssh <ALIAS> "hostname && uname -a"
```

### 5. Save Connection Info Locally

Create a local file `ssh_config.local` with connection details for reference:
```
Host: <ALIAS>
IP: <SERVER_IP>
Port: <PORT>
User: <USERNAME>
Key: ~/.ssh/id_ed25519
```

## Server Environment Quick Scan

After connecting, run these commands to get a quick overview:

```bash
# OS and hardware
echo "=== OS ===" && uname -a
echo "=== CPU ===" && nproc
echo "=== Memory ===" && free -h
echo "=== Disk ===" && df -h | grep -E "^/dev|^Filesystem"
echo "=== Conda ===" && conda env list 2>/dev/null || echo "No conda"
echo "=== Python ===" && python3 --version
echo "=== Pip ===" && python3 -m pip --version
```

## Directory Strategy

- Raw data: `/path/to/workspace/sra_data/`
- Analysis: `/path/to/workspace/<project_name>/`
- Large outputs: use the largest available disk (check `df -h`)

## Pitfall Warnings

- **Port blocking**: Some networks block non-standard SSH ports. Test with `ssh -v` for verbose output.
- **Known hosts**: First connection adds host key. Use `StrictHostKeyChecking accept-new` in config to auto-accept.
- **Key permissions**: `~/.ssh` must be 700, `authorized_keys` must be 644.
