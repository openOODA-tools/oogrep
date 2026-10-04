Name:           oogrep
Version:        0.2.0
Release:        1%{?dist}
Summary:        Capability-bounded recursive regex search
License:        ASL 2.0
URL:            https://github.com/openOODA-tools/oogrep
Source0:        oogrep-linux-x86_64
BuildArch:      x86_64
Requires:       glibc

%description
oogrep is a drop-in grep replacement written in openOODA, with
machine-readable JSON output and a first-class MCP surface for
agent callers.

%install
mkdir -p %{buildroot}/usr/bin
install -m 0755 %{SOURCE0} %{buildroot}/usr/bin/oogrep

%files
/usr/bin/oogrep

%changelog
* Sat Oct 03 2026 openOODA-tools <ops@openooda.org> - 0.2.0-1
- JSON output, .gitignore-aware search, MCP skipped telemetry
