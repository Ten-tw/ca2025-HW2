import sys
import numpy as np
import matplotlib.pyplot as plt

def parse_data(input_stream):
    """ Reads CSV data from stdin (updated: skips non-data lines, expects 3 columns) """
    x_vals = []
    y0_vals = []
    y1_vals = []

    found_header = False

    for line in input_stream:
        line = line.strip()
        if not line:
            continue

        if not found_header:
            # 修改標頭以匹配 C 語言輸出
            if 'x,y0,y1' in line:
                found_header = True
                print("Found CSV header 'x,y0,y1', starting data parsing...")
            else:
                pass # Silently skip log lines
            continue

        try:
            parts = line.split(',')
            # 修改為檢查 3 個部分
            if len(parts) == 3 and parts[0].isdigit():
                x = int(parts[0])
                y0 = int(parts[1])
                y1 = int(parts[2])

                x_vals.append(x)
                y0_vals.append(y0)
                y1_vals.append(y1)
            else:
                print(f"Skipping non-data line: {line}", file=sys.stderr)
                
        except (ValueError, IndexError):
            print(f"Warning: Skipping malformed data line: {line}", file=sys.stderr)
    
    if not found_header:
        print("Error: CSV header 'x,y0,y1' not found in input.", file=sys.stderr)
        return None

    # 修改為返回 3 個陣列
    return np.array(x_vals), np.array(y0_vals), np.array(y1_vals)

def calculate_errors(x_vals, y0_q16, y1_q16):
    """ Calculates absolute error in Q1.16 format (for 2 lines) """
    true_rsqrt_float = 1.0 / np.sqrt(x_vals)
    true_rsqrt_q16 = true_rsqrt_float * 65536.0
    
    err0 = np.abs(y0_q16 - true_rsqrt_q16)
    err1 = np.abs(y1_q16 - true_rsqrt_q16)
    
    # 修改為返回 2 個誤差陣列
    return err0, err1

def plot_errors(x_vals, err0, err1):
    """ Plots the error chart (for 2 lines) """
    plt.figure(figsize=(14, 8))
    
    plt.plot(x_vals, err0, 'o-', label='Error - Initial Guess (y0)', markersize=4)
    plt.plot(x_vals, err1, 's-', label='Error - 1 Iteration (y1)', markersize=4)
    # 移除了 y2 的繪圖
    
    plt.title('fast_rsqrt() Precision Analysis (1 Iteration)', fontsize=16)
    plt.xlabel('Input Value (x)', fontsize=12)
    plt.ylabel('Absolute Error (Q1.16 Units)', fontsize=12)
    
    # 新增這行來讓 X 軸刻度更密集
    plt.xticks(np.arange(0, 101, 10))
    
    plt.yscale('log')
    plt.legend(fontsize=11)
    plt.grid(True, which='both', linestyle='--', linewidth=0.5)
    
    output_filename = 'precision_iter1.png'
    plt.savefig(output_filename)
    print(f"Chart saved to '{output_filename}'")

def main():
    print("Reading C program output from stdin (1-Iteration Version)...")
    data = parse_data(sys.stdin)
    
    if data is None:
        print("Failed to parse data.")
        return

    x_vals, y0_q16, y1_q16 = data # 修改為接收 3 個變數
    
    if len(x_vals) == 0:
        print("No valid data was read.")
        return
        
    print(f"Successfully parsed {len(x_vals)} data points.")

    print("Calculating errors...")
    err0, err1 = calculate_errors(x_vals, y0_q16, y1_q16) # 修改為傳入 2 個變數
    
    print("Plotting chart...")
    plot_errors(x_vals, err0, err1) # 修改為傳入 2 個變數
    
    print("\n--- Error Statistics (Q1.16 Units) ---")
    print(f"Initial Guess (y0) - Mean Error: {np.mean(err0):.2f}, Max Error: {np.max(err0):.2f}")
    print(f"1st Iteration (y1) - Mean Error: {np.mean(err1):.2f}, Max Error: {np.max(err1):.2f}")
    # 移除了 y2 的統計

if __name__ == "__main__":
    main()