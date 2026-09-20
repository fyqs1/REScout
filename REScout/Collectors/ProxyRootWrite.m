#import "ProxyRootWrite.h"
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <signal.h>
#import <string.h>
#import <stdlib.h>

extern char **environ;

static int dov_run_argv(char *const argv[]) {
    if (!argv || !argv[0]) return -10;
    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    if (rc != 0) return rc;
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return -2;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return -3;
}

/// Run via /bin/sh so `printf password | sudo -S ...` is reliable (no race on stdin pipe).
static int dov_run_shell(NSString *script) {
    char *argv[] = { "/bin/sh", "-c", (char *)script.UTF8String, NULL };
    return dov_run_argv(argv);
}

static NSString *dov_sudo_bin(void) {
    NSArray *cands = @[
        @"/var/jb/usr/bin/sudo",
        @"/private/var/jb/usr/bin/sudo",
        @"/var/jb/bin/sudo",
        @"/usr/bin/sudo"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in cands) {
        NSString *r = p.stringByResolvingSymlinksInPath;
        if ([fm fileExistsAtPath:r]) return r;
        if ([fm fileExistsAtPath:p]) return p;
    }
    // Dopamine rootless resolved path
    NSString *jb = [@"/var/jb" stringByResolvingSymlinksInPath];
    if (jb.length) {
        NSString *p = [jb stringByAppendingPathComponent:@"usr/bin/sudo"];
        if ([fm fileExistsAtPath:p]) return p;
    }
    return @"/var/jb/usr/bin/sudo";
}

static NSString *dov_shell_quote(NSString *s) {
    // Wrap in single quotes; escape embedded single quotes.
    NSString *escaped = [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

static NSString *dov_sudo_cp(NSString *from, NSString *to) {
    NSString *sudo = dov_sudo_bin();
    // Device evidence: sudo -n always fails for mobile; -S with password works.
    NSString *script = [NSString stringWithFormat:
                        @"printf '123\\n' | %@ -S cp -f %@ %@",
                        dov_shell_quote(sudo),
                        dov_shell_quote(from),
                        dov_shell_quote(to)];
    int code = dov_run_shell(script);
    if (code == 0) return nil;

    // Fallback: tee
    script = [NSString stringWithFormat:
              @"printf '123\\n' | %@ -S tee %@ > /dev/null < %@",
              dov_shell_quote(sudo),
              dov_shell_quote(to),
              dov_shell_quote(from)];
    code = dov_run_shell(script);
    if (code == 0) return nil;

    return [NSString stringWithFormat:@"sudo cp/tee failed (%@ exit %d)", sudo, code];
}

static void dov_sudo_kick_configd(void) {
    NSString *sudo = dov_sudo_bin();
    NSString *script = [NSString stringWithFormat:
                        @"printf '123\\n' | %@ -S killall -HUP configd || true",
                        dov_shell_quote(sudo)];
    dov_run_shell(script);
}

NSString *DOVWriteDataToPathAsRoot(NSData *data, NSString *path) {
    if (data.length == 0 || path.length == 0) return @"empty write";

    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"REScout.preferences.%d.plist", (int)getpid()]];
    NSError *err = nil;
    if (![data writeToFile:tmp options:NSDataWritingAtomic error:&err]) {
        return err.localizedDescription ?: @"tmp write failed";
    }

    NSString *sudoErr = dov_sudo_cp(tmp, path);
    NSData *onDisk = [NSData dataWithContentsOfFile:path];
    BOOL readable = onDisk.length > 64;
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];

    if (sudoErr) {
        return [NSString stringWithFormat:@"%@; disk=%lu", sudoErr, (unsigned long)onDisk.length];
    }
    if (!readable) {
        return @"write verify failed (prefs unreadable)";
    }

    dov_sudo_kick_configd();
    return nil;
}

NSString *DOVKillPID(int pid) {
    if (pid <= 1) return @"invalid pid";
    if (kill(pid, SIGKILL) == 0) return nil;

    NSString *sudo = dov_sudo_bin();
    NSString *script = [NSString stringWithFormat:
                        @"printf '123\\n' | %@ -S kill -9 %d",
                        dov_shell_quote(sudo), pid];
    if (dov_run_shell(script) == 0) return nil;

    script = [NSString stringWithFormat:
              @"printf '123\\n' | %@ -S %@ -9 %d",
              dov_shell_quote(sudo),
              dov_shell_quote(@"/var/jb/usr/bin/kill"),
              pid];
    if (dov_run_shell(script) == 0) return nil;
    return [NSString stringWithFormat:@"kill %d failed", pid];
}

NSString *DOVKillallName(NSString *name) {
    if (name.length == 0) return @"empty name";
    NSString *sudo = dov_sudo_bin();
    NSString *script = [NSString stringWithFormat:
                        @"printf '123\\n' | %@ -S killall -9 %@",
                        dov_shell_quote(sudo),
                        dov_shell_quote(name)];
    if (dov_run_shell(script) == 0) return nil;
    script = [NSString stringWithFormat:
              @"printf '123\\n' | %@ -S %@ -9 %@",
              dov_shell_quote(sudo),
              dov_shell_quote(@"/var/jb/usr/bin/killall"),
              dov_shell_quote(name)];
    if (dov_run_shell(script) == 0) return nil;
    return [NSString stringWithFormat:@"killall %@ failed", name];
}
