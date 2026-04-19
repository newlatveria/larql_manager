#!/bin/bash

# --- Stylization ---
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuration ---
REPO_URL="https://github.com/newlatveria/larql_manager.git"
INSTALL_DIR="$HOME/.local/share/larql-manager"
BINARY_PATH="$HOME/.local/bin/larql-manager"

clear
echo -e "${CYAN}${BOLD}=============================================="
echo -e "   LARQL MANAGER: Novice-Friendly Installer   "
echo -e "         Targeting Ubuntu 24.04 LTS           "
echo -e "==============================================${NC}\n"

# --- Logical Feedback Loop: Dependency Check ---
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}[!] Missing requirement:${NC} $1"
        read -p "    May I install $2? (y/n): " confirm
        if [[ $confirm == [yY] ]]; then
            sudo apt update && sudo apt install -y "$2"
        else
            echo -e "${RED}Critical dependency missing. Exiting.${NC}"
            exit 1
        fi
    fi
}

# --- STEP 1 ---
install_process() {
    echo -e "${CYAN}--- Step 1: Checking System Environment ---${NC}"
    check_dependency "git" "git"
    check_dependency "pkg-config" "pkg-config"
    check_dependency "cargo" "cargo" # This handles Rust
    check_dependency "gcc" "build-essential"

# --- STEP 2 ---    
    # UI Dependencies for 24.04
    echo -e "${CYAN}--- Step 2: Preparing UI Framework (GTK4/Adwaita) ---${NC}"
    sudo apt install -y libgtk-4-dev libadwaita-1-dev

# --- STEP 3 ---
    echo -e "${CYAN}--- Step 3: Fetching LARQL Manager Source ---${NC}"
    if [ -d "$INSTALL_DIR" ]; then
        echo "Found existing folder. Updating..."
        cd "$INSTALL_DIR" && git pull
    else
        git clone -b dev "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi

# --- STEP 4 ---
echo -e "${CYAN}--- Step 4: Building LARQL & Server Components ---${NC}"
    # Build the main manager
    cargo build --release
    
    # Install the server component so 'serve' works
    echo -e "${YELLOW}Installing larql-server crate...${NC}"
    cargo install --path crates/larql-server

# --- STEP 5 ---
echo -e "${CYAN}--- Step 5: Finalizing Installation ---${NC}"
    mkdir -p "$HOME/.local/bin"
    
# --- STEP 6 --- Smart Discovery of the binary (handles larql_manager or larql-manager)
    BIN_NAME=$(find target/release -maxdepth 1 -type f -executable -name "larql*" | head -n 1)

    if [ -n "$BIN_NAME" ]; then
        cp "$BIN_NAME" "$BINARY_PATH"
        chmod +x "$BINARY_PATH"
        echo -e "${GREEN}Binary installed to $BINARY_PATH${NC}"
    else
        echo -e "${RED}Error: Could not find the compiled binary in target/release.${NC}"
        exit 1
    fi

# --- STEP 7 ---    
    # Create Desktop Entry with a standard AI-themed icon for Ubuntu 24.04
    cat <<EOF > "$HOME/.local/share/applications/larql-manager.desktop"
[Desktop Entry]
Name=LARQL Manager
Exec=$BINARY_PATH
Icon=org.gnome.Settings-symbolic
Type=Application
Categories=Development;Science;IDE;
Terminal=false
EOF
    # Force Ubuntu to notice the new desktop file
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null

    echo -e "\n${GREEN}${BOLD}✓ ACTUAL SUCCESS!${NC} You can now launch LARQL Manager."
}

uninstall_process() {
    echo -e "${RED}--- Removing LARQL Manager ---${NC}"
    read -p "Are you sure you want to remove the app and all configuration? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        rm -rf "$INSTALL_DIR"
        rm "$BINARY_PATH"
        rm "$HOME/.local/share/applications/larql-manager.desktop"
        echo -e "${GREEN}Cleanup complete.${NC}"
    fi
}

discover_models() {
    echo -e "${CYAN}--- Smart Auto-Discovery Mode ---${NC}"
    echo "Scanning /home/$USER for usable models..."
    
    # --- Spinner Logic ---
    spinner() {
        local pid=$1
        local delay=0.1
        local spinstr='|/-\'
        while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
            local temp=${spinstr#?}
            printf " [%c]  " "$spinstr"
            local spinstr=$temp${spinstr%"$temp"}
            sleep $delay
            printf "\b\b\b\b\b\b"
        done
        printf "    \b\b\b\b"
    }

    # 1. Define the search path 
    SEARCH_PATH="$HOME"
    
    # 2. Logic: Find files ending in .gguf or .safetensors 
    # BUT must be larger than 500MB to ignore vocab/metadata files.
    # We also exclude "vocab" in the filename for extra safety.
    SMART_MODELS=$(find "$SEARCH_PATH" -type f \( -name "*.gguf" -o -name "*.safetensors" \) \
                  -size +500M \
                  ! -name "*vocab*" 2>/dev/null)
    
FIND_PID=$!
    
    # Start the spinner and wait for the find PID
    spinner "$FIND_PID"

    if [ -z "$SMART_MODELS" ]; then
        echo -e "${RED}No large models found in $SEARCH_PATH.${NC}"
        echo "Tip: Make sure your files are in a folder the script can see."
    else
        echo -e "${GREEN}Detected Primary Models:${NC}"
        # Loop through found models to present them cleanly
        while IFS= read -r line; do
            FILE_SIZE=$(du -h "$line" | cut -f1)
            echo -e "  [ $FILE_SIZE ] -> $(basename "$line")"
        done <<< "$SMART_MODELS"
        
        echo -e "\n${BOLD}Discovery complete.${NC} These are ready for LARQL Patching."
    fi
    read -p "Press Enter to return to menu..."
}

select_model_from_list() {
    # 1. Get unique files only to avoid duplicates in the menu
    # 2. Show the parent folder so you know which Qwen3.5 is which
    UNIQUE_MODELS=$(echo "$SMART_MODELS" | tr ' ' '\n' | sort -u)
    
    if [ -z "$UNIQUE_MODELS" ]; then
        echo -e "${RED}No models found. Enter path manually:${NC}"
        read -e -p "Path: " SELECTED_MODEL
    else
        echo -e "Discovered Models:"
        mapfile -t model_array <<< "$UNIQUE_MODELS"
        for i in "${!model_array[@]}"; do
            path="${model_array[$i]}"
            # Shows 'folder/filename'
            echo "$((i+1))) $(basename "$(dirname "$path")")/$(basename "$path")"
        done
        read -p "Pick a number: " m_num
        SELECTED_MODEL="${model_array[$((m_num-1))]}"
    fi
}

larql_workflow_menu() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}=== LARQL OPERATIONAL WORKFLOWS ===${NC}"
        echo -e "1) ${BOLD}Decompile Model${NC} (GGUF → .vindex)"
        echo -e "2) ${BOLD}Explore Knowledge${NC} (Query/Describe/REPL)"
        echo -e "3) ${BOLD}Modify/Patch${NC} (Build/Merge/Filter)"
        echo -e "4) ${BOLD}Deep Analysis${NC} (SVD/Circuits/FFN-Bench)"
        echo -e "5) Back to Main Menu"
        read -p "Select a workflow [1-5]: " wf_choice

        case $wf_choice in
            1) # DECOMPILE
                select_model_from_list
                [ -z "$SELECTED_MODEL" ] && continue
                
                # PRE-FLIGHT CHECK: Tokenizer
                MODEL_DIR=$(dirname "$SELECTED_MODEL")

                if [ ! -f "$MODEL_DIR/tokenizer.json" ]; then
                    echo -e "${RED}Error:${NC} No tokenizer.json found in $MODEL_DIR"
                    echo -e "${YELLOW}Hint:${NC} Download it from HuggingFace and place it next to the model."
                    read -p "Press Enter to skip..."
                    continue
                fi

                read -p "Enter output name (default: model.vindex): " vname
                vname=${vname:-model.vindex}
                
                echo -e "${YELLOW}Decompiling...${NC}"
                # FIXED: Position argument used correctly here
                "$BINARY_PATH" extract-index --output "$vname" "$SELECTED_MODEL"
                ;;

            2) # EXPLORE
                read -e -p "Path to .vindex file: " VFILE
                if [ ! -f "$VFILE" ]; then echo "File not found!"; sleep 1; continue; fi
                echo -e "1) Ask Fact  2) Describe Entity  3) REPL"
                read -p "Choice: " ex_choice
                case $ex_choice in
                    1) read -p "Query: " q; "$BINARY_PATH" lql "$q" "$VFILE" ;;
                    2) read -p "Entity: " ent; "$BINARY_PATH" describe "$ent" "$VFILE" ;;
                    3) "$BINARY_PATH" repl "$VFILE" ;;
                esac
                ;;

            3) # PATCH
                read -e -p "Base Graph: " ga
                read -e -p "Patch Graph: " gb
                "$BINARY_PATH" merge --output merged.vindex "$ga" "$gb"
                ;;

            4) # ANALYSIS
                echo -e "1) FFN-Bench  2) Circuit-Discover"
                read -p "Choice: " a_choice
                [ "$a_choice" == "1" ] && "$BINARY_PATH" ffn-bench
                if [ "$a_choice" == "2" ]; then
                    read -e -p "Model Path: " m; "$BINARY_PATH" circuit-discover "$m"
                fi
                ;;

            5) return ;;
        esac
        read -p "Press Enter to continue..."
    done
}

# --- Main Menu Loop ---
while true; do
    echo -e "\n${BOLD}What would you like to do?${NC}"
    echo "1) Install / Update LARQL Manager"
    echo "2) Uninstall LARQL Manager"
    echo "3) Scan for AI Models (Discovery)"
    echo "4) 🚀 Start LARQL Manager"
    echo "5) Exit"
    read -p "Selection [1-5]: " choice

    case $choice in
        1) install_process ;;
        2) uninstall_process ;;
        3) discover_models ;;
4) 
            if [ -f "$BINARY_PATH" ]; then
                larql_workflow_menu
            else
                echo -e "${RED}App not installed. Please run Option 1 first.${NC}"
                read -p "Press Enter..."
            fi
            ;;
        5) exit 0 ;;
        *) echo -e "${RED}Invalid option.${NC}" ;;
    esac
done
