
# How to make the file list
ls ~/scratch/DetectionRadar/Inputs/XAM_2013/XAM_201307* | xargs -n 1 basename > XAM_201307.filelist

# How to save the percentages of detection from the output files:
for i in *.out; do grep -a "detection_" $i | tail -1 |   grep -oP '[0-9]+\.[0-9]+(?=%)|[0-9]{12}' | paste -sd',' | awk -v fname="$(basename "$i")" '{print $0 "," fname}'; done > a

# How to calculate a percentage of cells over a certain threshold using cdo
load module cdo
for i in $(ls *.nc | cut -d _ -f 2); do echo $i,`cdo -s -output -mulc,100 -fldmean -gtc,0.7 -selname,probability detection_"$i"_probability.nc 2>/dev/null`; done > ~/Radar/BUDSCAN/XAM_2013_07pct.txt
