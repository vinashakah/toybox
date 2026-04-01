#!/data/data/com.termux/files/usr/bin/bash

###########################################
## I just killed an annoying ugly fly.   ##
## Now come home and eat the tasty meal! ##
###########################################


declare -a package_list=("autoconf" "automake" "gettext" "libtool" "proot" "xfce4-dev-tools" "xorgproto")
declare -i total_tries=

if (($# == 0)); then
    echo "Don't mess up here, or it'll become very time wasting then."
    exit 1
fi

printf "\033[1;4;33m"
echo -n "Warning:"
printf "\033[0m"
echo " To make this working perfectly fine, confirm installation of XFCE Desktop Environment and then execute it, or press [Ctrl+C] combination."
echo -n "Waiting for user interruption... "
sleep 3
echo "Time's Up."
cd "$PREFIX/tmp"

while true; do
    if ((total_tries == 5)); then
        echo "Never thought to stuck here, it's a very silly situation for real."
        sleep 3
        total_tries=
    fi

    dpkg -V ${package_list[@]} || pkg --check-mirror add ${package_list[@]} -y || ((++ total_tries)) && continue
    curl "https://www.github.com/xfce-mirror/xfce4-wavelan-plugin/archive/refs/tags/xfce4-wavelan-plugin-0.6.4.zip" -L -O || ((++ total_tries)) && continue
    echo "Let's rock!"
    clear
    break
done

echo "Compiling manually..."
unzip -o "xfce4-wavelan-plugin-0.6.4.zip"
cd "xfce4-wavelan-plugin-xfce4-wavelan-plugin-0.6.4"
rm "panel-plugin/wi_linux.c"
cat > "panel-plugin/wi_linux.c" << "EOF"
/*
 * Written + Tested, by Kyka -> No restrictions whatsoever.
 *
 * Everyone is allowed to copy, edit and use,
 * but permission to redistribute without credit
 * is strictly denied, so please at least keep me.
 *
 * Contact: GitHub (@vinashakah)
 * Description: Recreated Wi-Fi status checker and information fetcher supporting only Android.
 */



#if defined(__linux__)


#include <libxfce4util/libxfce4util.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sys/time.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <stdbool.h>
#include <wi.h>

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif


// We don't need socket anymore, but keeping the structure
// so the rest of the Xfce plugin doesn't break down.
struct wi_device
{
    char interface[WI_MAXSTRLEN];
};

// Added the missing semicolon here, thanks Gemini brother to enhance my bad habit.

struct wi_device * wi_open(const char * interface)
{
    struct wi_device * device;

    g_return_val_if_fail(interface != NULL, NULL);
    TRACE("Opening pseudo-device for Termux on %s", interface);
    device = g_new0(struct wi_device, 1);
    g_strlcpy(device -> interface, interface, WI_MAXSTRLEN);

    return(device);
};

void wi_close(struct wi_device * device)
{
    g_free(device);
};

// Helper function to run the Termux API command and grab JSON
static int read_wifi_status(char * buffer, size_t buf_size) 
{
    int pipefd[2], status;
    pid_t pid;

    if (pipe(pipefd) == -1) return 0;

    if ((pid = fork()) == 0) {
        // Child Process

        close(pipefd[0]); // Close write end
        dup2(pipefd[1], STDOUT_FILENO); // Redirect stdout to pipe
        dup2(pipefd[1], STDERR_FILENO); // Redirect stderr too
        close(pipefd[1]);
        execlp("termux-wifi-connectioninfo", "termux-wifi-connectioninfo", NULL);
        perror("Can't create process to run the command"); // If exec fails
        exit(EXIT_FAILURE); // !! Danger Zone !!
    } else if (pid > 0) {
        // Parent Process

        close(pipefd[1]); // Always close the write end in the parent!

        int flags = fcntl(pipefd[0], F_GETFL, 0);
        ssize_t total_bytes = 0;
        struct timeval timeout;
        fd_set readfds;

        // Apply FIX 3: Make the read end of the pipe STRICTLY non-blocking
        fcntl(pipefd[0], F_SETFL, flags | O_NONBLOCK);

        // Loop to ensure we get the full payload
        while (true) {
            // Set the safety timer limit once for the whole operation
            timeout.tv_sec = 15;
            timeout.tv_usec = 0;

            // Initialize the file descriptor set
            FD_ZERO(& readfds);
            FD_SET(pipefd[0], & readfds);

            // Wait for activity
            int retval = select(pipefd[0] + 1, & readfds, NULL, NULL, & timeout);

            // Sharp Eye here: Timer starts fresh (progress reset) for every chunk
            if (retval == -1) {
                // Something wicked happened.
                if (errno == EINTR) continue;

                // For error handling
                perror("Failed to attach work inspector");
                kill(pid, SIGKILL);
                close(pipefd[0]);

                // Graceful quitting instead of deadly panel crash!
                return 0;
            } else if (retval == 0) {
                printf("Time's Up. Killing process %d ...\n", pid);
                kill(pid, SIGKILL);
                close(pipefd[0]);

                return 0;
            } else {
                // Data is available
                ssize_t bytesRead = read(pipefd[0], buffer + total_bytes, buf_size - total_bytes - 1);

                if (bytesRead > 0) {
                    total_bytes += bytesRead;
                    if (total_bytes >= (ssize_t)(buf_size) - 1) break; // Buffer full protection
                } else if (bytesRead == 0 || (errno != EAGAIN && errno != EWOULDBLOCK)) break; // Process finished outputting
            };
        };

        // End of file
        buffer[total_bytes] = '\0';

        // Clean up zombie process
        close(pipefd[0]);
        waitpid(pid, & status, 0);

        // Now it is guaranteed to be as complete as possible
        return 1;
    };

    return 0;
};

int wi_query(struct wi_device * device, struct wi_stats * stats)
{
    bool is_label_hidden = false;
    char buffer[2048], * buf_ptr;
    int rssi = -54;

    g_return_val_if_fail(device != NULL, WI_INVAL);
    g_return_val_if_fail(stats != NULL, WI_INVAL);

    // Set some defaults
    g_strlcpy(stats -> ws_qunit, "%", 2);
    g_strlcpy(stats -> ws_vendor, "Termux", WI_MAXSTRLEN);
    g_strlcpy(stats -> ws_netname, "Unknown", WI_MAXSTRLEN);
    stats -> ws_rate = 0;
    stats -> ws_quality = 0;

    if (! read_wifi_status(buffer, sizeof(buffer))) return WI_NOSUCHDEV;

    // Check if we actually have a connection
    buf_ptr = strstr(buffer, "\"supplicant_state\"");

    if (buf_ptr == NULL) return WI_NOSUCHDEV; // If there's no supplicant state at all, the device is missing
    else {
        char state[32] = {
            0
        };

        // Extract exactly what the state is, safely
        if (sscanf(buf_ptr, "\"supplicant_state\": \"%31[^\"]\"", state) == 1) {
            if (strcmp(state, "COMPLETED") != 0) return WI_NOCARRIER; // If it's NOT "COMPLETED", we have no carrier.
        } else return WI_NOCARRIER;
    };

    // If it IS "COMPLETED", we just let the code continue downward!

    // 0. Check Hidden Status
    buf_ptr = strstr(buffer, "\"ssid_hidden\"");

    if (buf_ptr != NULL) {
        char fake_val[10] = {
            0
        };

        if (sscanf(buf_ptr, "\"ssid_hidden\": %9[^, \n}]", fake_val) == 1) if (strcmp(fake_val, "true") == 0) is_label_hidden = true;
    };

    // 1. Get SSID (Network Name)
    buf_ptr = strstr(buffer, "\"ssid\"");

    if (buf_ptr != NULL) {
        buf_ptr = strstr(buf_ptr, ": \"");

        if (buf_ptr != NULL) {
            buf_ptr += 3; // Skip the ': "', like a simple Regular Expression.

            char * end_quote = strchr(buf_ptr, '"');

            if (end_quote != NULL) {
                // Create a temporary buffer to check the string
                char label[WI_MAXSTRLEN];
                int len = end_quote - buf_ptr;

                if (len >= WI_MAXSTRLEN) len = WI_MAXSTRLEN - 1;

                strncpy(label, buf_ptr, len);
                label[len] = '\0';

                // Condition: Only update if it is NOT "<unknown ssid>"
                // Logic Update: (*** Troll Proof?! ***)
                // If it's actually hidden for security purpose excuse (who'll hack only by name, silly idea), we show "Unknown".
                // If NOT hidden (it could be possible with root right?), we set the name even if the SSID looks like "<unknown ssid>".
                if (! is_label_hidden) g_strlcpy(stats -> ws_netname, label, WI_MAXSTRLEN);
            };
        };
    };

    // 2. Get Bit Rate (Speed in Mbps)
    buf_ptr = strstr(buffer, "\"link_speed_mbps\"");

    if (buf_ptr != NULL) {
        // Extracting directly into a double as the original code expects
        int rate = 0;

        if (sscanf(buf_ptr, "\"link_speed_mbps\": %d", & rate) == 1) stats -> ws_rate = rate;
    };

    // 3. Get RSSI and Calculate Quality Percentage
    buf_ptr = strstr(buffer, "\"rssi\"");

    if (buf_ptr != NULL) {
        sscanf(buf_ptr, "\"rssi\": %d", & rssi);

        /* *** RSSI is usually between -100 (terrible) and -50 (perfect) ***
         * We use a simple linear equation to map this to 0-100%.
         * Formula: 2 * (RSSI + 100)
         */

        int quality = 2 * (rssi + 100);

        // Clamp values to make sure we don't go over 100% or under 0%
        if (quality > 100) quality = 100;
        if (quality < 0) quality = 0;

        stats -> ws_quality = quality;
        TRACE("Network RSSI: %d, Calculated Quality: %d%%", rssi, quality);
    };

    // If Xfce Devs include another/more information transferrer in future updates,
    // I will possibly add them after that, you can let me know by reporting an issue.

    return(WI_OK);
};


#endif
EOF
bash "autogen.sh"
termux-chroot "cd $(pwd) && make $@"
echo "Cleaning garbage..."
pkg rm ${package_list[@]} -y
apt autoremove -y
echo "Leftover remainder: $(pwd)"
echo "If everything goes as planned, that's awesome!"
