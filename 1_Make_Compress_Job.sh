#!/bin/bash
# Usage: bash make_compress_job.sh /path/to/directory
 
set -e
 
# --- Check argument ---
if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/directory"
    exit 1
fi
 
DIR=$(realpath "$1")
 
if [ ! -d "$DIR" ]; then
    echo "Error: '$DIR' is not a directory."
    exit 1
fi
 
# --- Collect files (non-compressed, non-empty) ---
DAYLIST="$DIR/.compress_daylist.txt"

ls $DIR/*.nc | xargs -n 1 basename | cut -d _ -f 2 | cut -c 1-8 | uniq  > "$DAYLIST"

NDAYS=$(wc -l < "$DAYLIST")

if [ "$NDAYS" -eq 0 ]; then
    echo "No uncompressed files found in '$DIR'."
    rm "$DAYLIST"
    exit 0
fi

echo "Found $NDAYS day(s) to compress."

# --- Write SLURM script ---
JOBSCRIPT="$DIR/compress_array.sh"

cat > "$JOBSCRIPT" << EOF
#!/bin/bash
#SBATCH --job-name=compress
#SBATCH --array=1-${NDAYS}
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:15:00
#SBATCH --mail-type=ALL
#SBATCH --mail-user=jean.noel.candau@gmail.com

mkdir -p ${DIR}/logs

# Get the file for this array task
YMD=\$(sed -n "\${SLURM_ARRAY_TASK_ID}p" "$DAYLIST")

if [ -z "XAM_\${YMD}.tar.gz" ]; then
    echo "No file for task \$SLURM_ARRAY_TASK_ID"
    exit 1
fi

echo "Compressing: \$YMD"

cd ${DIR}
tar -I pigz -cf XAM_\${YMD}.tar.gz XAM_\${YMD}*.nc --remove-files

echo "Done: \${YMD}.gz"
EOF

chmod +x "$JOBSCRIPT"

echo "SLURM script written to: $JOBSCRIPT"
echo "File list written to:    $DAYLIST"
echo ""
echo "Submit with:"
echo "  sbatch $JOBSCRIPT"
