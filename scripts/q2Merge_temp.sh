# 系統組成表をtaxonomic rankごとに分割して要約
## taxonomicランク列及びサンプル列を指定
OTT='taxonomy_cnt.tsv'
ncol=`head -1 ${OTT} | awk -F"\t" '{print NF}'`
ismp=10
smps=(`head -1 ${OTT} | cut -f${ismp}-`)
ntax=(`seq 3 $((${ismp}-1))`)
nsmp=(`seq ${ismp} ${ncol}`)

## taxonomic rankの判定　silva, greengene, pr2
rank1=`head -1 ${OTT} | cut -f3`; rank2=`head -1 ${OTT} | cut -f4`
if [[ $rank1 = 'd' && $rank2 = 'p' ]]; then
  rank=(domain phylum class order family genus species)
elif [[ $rank1 = 'k' && $rank2 = 'p' ]]; then
  rank=(kingdom phylum class order family genus species)
elif [[ $rank1 = 'd' && ! $rank2 = 'p' ]]; then
  rank=(domain supergroup phylum class order family genus species)
fi

# Check args
#echo $OTT
#echo -e "[Number of columns]\t"$ncol
#echo -e "[Column positions of samples]\t"${nsmp[@]}
#echo -e "[Column positions of taxonomy]\t"${ntax[@]}
echo -e "[Names of samples]\t"${smps[@]}
echo -e "[Names of taxonomic rank]\t"${rank[@]}

## 一時ファイルを格納するディレクトリ
temp_cnt=$(mktemp -d)
trap 'rm -rf $temp_cnt' EXIT

## rank毎に行持ちデータフレームを作成し、要約
for j in ${!ntax[@]}; do
  ptax=${ntax[$j]}; tax=${rank[$j]}
  for i in ${!nsmp[@]}; do
    psmp=${nsmp[$i]}; smp=${smps[$i]}
    cut -f${ptax},${psmp} ${OTT} | sed -e '1d' \
    | awk -F"\t" -v smp="${smp}" '{if($1==""){$1="Unassigned"}; arr[$1]+=$2}END{for(x in arr)print x"\t"smp"\t"arr[x]}'
  done > ${temp_cnt}/${tax}.cnt
done

## 列持ちデータに変換
abr=(`for i in ${rank[@]}; do echo ${i:0:1}; done`)
for k in ${!rank[@]}; do 
  rnk=${rank[$k]}
  in=${temp_cnt}/${rnk}.cnt
  out=count_${abr[$k]}.dat

 for x in ${smps[@]}; do 
  grep ${x} ${in} | cut -f1,3 | sort -t$'\t' -k1,1> ${temp_cnt}/${rnk}_${x}.tmp
 done
 
n_temp=`ls ${temp_cnt}/*.tmp | wc -l` # sample numbers
slct=(`seq 2 2 $((${n_temp}*2))`) # column numbers of count data only
echo -e "taxon "${smps[*]} | tr ' ' '\t' > ${out}
paste ${temp_cnt}/${rnk}*.tmp | cut -f1,`echo ${slct[@]}|tr ' ' ','`  >> ${out}

done