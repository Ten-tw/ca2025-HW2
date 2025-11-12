import sys
import numpy as np
import matplotlib.pyplot as plt

# --- 已移除中文 RParams ---

def parse_data(input_stream):
    """ Reads CSV data from stdin (updated: skips non-data lines) """
    x_vals = []
    y0_vals = []
    y1_vals = []
    y2_vals = []

    found_header = False

    for line in input_stream:
        line = line.strip()
        if not line:
            continue

        if not found_header:
            if 'x,y0,y1,y2' in line:
                found_header = True
                print("Found CSV header 'x,y0,y1,y2', starting data parsing...")
            else:
                # Silently skip log lines
                pass
            continue

        try:
            parts = line.split(',')
            if len(parts) == 4 and parts[0].isdigit():
                x = int(parts[0])
                y0 = int(parts[1])
                y1 = int(parts[2])
                y2 = int(parts[3])

                x_vals.append(x)
                y0_vals.append(y0)
                y1_vals.append(y1)
                y2_vals.append(y2)
            else:
                # Probably a log line at the end
                print(f"Skipping non-data line: {line}", file=sys.stderr)
                
        except (ValueError, IndexError):
            print(f"Warning: Skipping malformed data line: {line}", file=sys.stderr)
    
    if not found_header:
        print("Error: CSV header 'x,y0,y1,y2' not found in input.", file=sys.stderr)
        return None

    return np.array(x_vals), np.array(y0_vals), np.array(y1_vals), np.array(y2_vals)

def calculate_errors(x_vals, y0_q16, y1_q16, y2_q16):
    """ Calculates absolute error in Q1.16 format """
    true_rsqrt_float = 1.0 / np.sqrt(x_vals)
    true_rsqrt_q16 = true_rsqrt_float * 65536.0
    
    err0 = np.abs(y0_q16 - true_rsqrt_q16)
    err1 = np.abs(y1_q16 - true_rsqrt_q16)
    err2 = np.abs(y2_q16 - true_rsqrt_q16)
    
    return err0, err1, err2

def plot_errors(x_vals, err0, err1, err2):
    """ Plots the error chart """
    plt.figure(figsize=(14, 8))
    
    # --- 英文標籤 ---
    plt.plot(x_vals, err0, 'o-', label='Error - Initial Guess (y0)', markersize=4)
    plt.plot(x_vals, err1, 's-', label='Error - 1 Iteration (y1)', markersize=4)
    plt.plot(x_vals, err2, '^-', label='Error - 2 Iterations (y2)', markersize=4)
    
    plt.title('fast_rsqrt() Precision Analysis (x=1 to 100)', fontsize=16)
    plt.xlabel('Input Value (x)', fontsize=12)
    plt.ylabel('Absolute Error (Q1.16 Units)', fontsize=12)
    
    # --- 新增這行來讓 X 軸刻度更密集 ---
    plt.xticks(np.arange(0, 101, 10))
    # --- 結束 ---
    
    plt.yscale('log')
    plt.legend(fontsize=11)
    plt.grid(True, which='both', linestyle='--', linewidth=0.5)
    
    output_filename = 'precision_iter2.png'
    plt.savefig(output_filename)
    print(f"Chart saved to '{output_filename}'")

def main():
    print("Reading C program output from stdin (filtering logs)...")
    data = parse_data(sys.stdin)
    
    if data is None:
        print("Failed to parse data.")
        return

    x_vals, y0_q16, y1_q16, y2_q16 = data
    
    if len(x_vals) == 0:
        print("No valid data was read.")
        return
        
    print(f"Successfully parsed {len(x_vals)} data points.")

    print("Calculating errors...")
    err0, err1, err2 = calculate_errors(x_vals, y0_q16, y1_q16, y2_q16)
    
    print("Plotting chart...")
    plot_errors(x_vals, err0, err1, err2)
    
    # --- 英文統計 ---
    print("\n--- Error Statistics (Q1.16 Units) ---")
    print(f"Initial Guess (y0) - Mean Error: {np.mean(err0):.2f}, Max Error: {np.max(err0):.2f}")
    print(f"1st Iteration (y1) - Mean Error: {np.mean(err1):.2f}, Max Error: {np.max(err1):.2f}")
    print(f"2nd Iteration (y2) - Mean Error: {np.mean(err2):.2f}, Max Error: {np.max(err2):.2f}")

if __name__ == "__main__":
    main()