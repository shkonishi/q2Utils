#!/bin/bash
VERSION=0.0.231202
AUTHOR=SHOGO_KONISHI
CMDNAME=$(basename $0)

# NOTE: anaconda/miniconda 判別
# NOTE: observed_otus / observed_features 選択


### Contents: Diversity ###
# 1. ドキュメント
#  1.1. ヘルプの表示 
#  1.2. 使用例の表示
# 2. オプション引数の処理
# 3. コマンドライン引数の処理
# 4. プログラムに渡す引数の一覧 
# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
#  5.2. 関数定義
#  5.3. feature-tableから最小リードデプスを取得
#  5.4. レアファクションカーブ [qiime diversity alpha-rarefaction] 
#  5.5. alpha diversity 比較 & クラスカルウォリス検定 [qiime diversity alpha-group-significance]
#  5.6. Beta diversity [ qiime diversity core-metrics-phylogenetic ]
#  5.7. Beta-diversity per SampleType [qiime diversity beta-group-significance]
#  5.8. PCoAスコアと寄与率、及びalpha-diversityをtsvに変換
#  5.9. Heatmap
###


# 1. ドキュメント
#  1.1. ヘルプの表示 
function print_doc() {
cat << EOS
使用法:
  $CMDNAME [オプション]
   
説明:
  このプログラムではqiime2のfeature tableと検体のメタデータファイルを入力として、多様性解析を行います。
  オプションとして系統解析データ(rooted-tree.qza)を追加した場合、レアファクションカーブの描画とベータ多様性解析
  オプションとしてtaxonomyデータ(taxonomy.qza)を追加した場合、heatmapを作成します。
  レアファクションカーブを描画する場合、最小リード数を指定する必要があり、feature-tableから最小リード数を取得します。
  またメタデータファイルをオプションで指定することも可能です。

  # 01_alpha-rarefaction
  # 02_Kruskal-wallis test of alpha-diversity
  # 03_PCoA plots of beta diversity 
  # 04_heatmap_with_HCA

  qiime diversity alpha-rarefaction
  qiime diversity alpha
  qiime diversity alpha-group-significance adjusted p-value of Benjamini & Hochberg correction.
  qiime diversity core-metrics-phylogenetic
  qiime diversity beta-group-significance
  qiime feature-table filter-features
  qiime taxa collapse
  qiime feature-table heatmap

オプション: 
  -e    conda環境変数パス[default: ${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2022.2 ]
  -m    メタデータファイル[default: map.txt]
  -r    rooted-tree.qza
  -x    taxonomy.qza
  -t    feature-table.qza
  -h    ヘルプドキュメントの表示

使用例:
  $CMDNAME -m map.txt -r rooted-tree.qza -x taxonomy.qza -t table.qza 

EOS
}

if [[ "$#" = 0 ]]; then print_doc ; exit 1 ; fi

# 2. オプション引数の処理
## 2.1. オプション引数の入力
while getopts e:q:m:r:x:t:h OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;    
    "m" ) META="$OPTARG";;
    "r" ) TRE="$OPTARG";;    
    "x" ) TAX="$OPTARG";;
    "t" ) TAB="$OPTARG";;
    "h" ) print_doc ; exit 1 ;; 
    *) print_doc ; exit 1 ;; 
    \? ) print_doc ; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

## 2.2. conda環境変数ファイルの存在確認
if [[ -z "$CENV" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; fi
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}" >&2 ; exit 1
fi

## 2.3. qiime2環境の存在確認
if [[ -z "$QENV" ]]; then QENV='qiime2-2022.2'; fi
conda info --env | grep -q $QENV || { echo "[ERROR] There is no ${QENV} environment."  >&2 ; conda info --envs >&2 ; exit 1 ; }


##  2.4. オプション引数の判定およびデフォルト値の指定
## Metadata
if [[ -z "$META" ]]; then META='map.txt'; fi
if [[ -f "${META}" ]]; then
  NST=$(($(cat ${META} | awk -F"\t" 'NR==1{print NF}' )-1))
else 
  echo -e "[ERROR] There is not meta-data file." >&2 ; exit 1
fi
## TREE
if [[ -z "$TRE" ]]; then TRE='rooted-tree.qza'; fi
if [[ ! -f "${TRE}" ]] ; then echo "[ERROR] The ${TRE} could not find." >&2 ; exit 1; fi
## TAXONOMY
if [[ -z "$TAX" ]]; then TAX='taxonomy.qza'; fi
if [[ ! -f "${TAX}" ]] ; then echo "[ERROR] The ${TAX} could not find." >&2 ; exit 1; fi
## TABLE
if [[ -z "$TAB" ]]; then TAB='table.qza'; fi
if [[ ! -f "${TAB}" ]] ; then echo "[ERROR] The ${TAB} could not find." >&2 ; exit 1; fi

## その他引数初期値
OUTV='diversity_qzv' 
OUTA='diversity_qza'
OUTT='diversity_tsv'
OUTAST="${OUTV}/alpha-rarefaction_SampleType.qzv"
OUTASD="${OUTV}/alpha-rarefaction_SampleID.qzv"
ALP=(chao1 simpson shannon)

# 3. コマンドライン引数の処理 (無し)

# 4. プログラムに渡す引数の一覧 
cat << EOS >&2

### Diversity analysis ###
  conda environmental variables : [ ${CENV} ]
  qiime2 environment :            [ ${QENV} ]
  count table:                    [ $TAB ]
  rooted tree:                    [ $TRE ]
  taxonomy:                       [ $TAX ]
  metadata:                       [ $META ]
  sample type:                    [ $NST ]
  alpha-diversity metrics:        [ ${ALP[*]} ]

  output rarefaction sampletype:  [ ${OUTAST} ]
  output rarefaction sampleID:    [ ${OUTASD} ]

  output diversity analysis qzv:  [ ${OUTV} ]
  output diversity analysis qza:  [ ${OUTA} ]
  output diversity analysis tsv:  [ ${OUTT} ]

EOS

# Saved FeatureTable[Frequency] to: Beta_diversity/rarefied_table.qza
# Saved SampleData[AlphaDiversity] to: Beta_diversity/faith_pd_vector.qza
# Saved SampleData[AlphaDiversity] to: Beta_diversity/observed_features_vector.qza
# Saved SampleData[AlphaDiversity] to: Beta_diversity/shannon_vector.qza
# Saved SampleData[AlphaDiversity] to: Beta_diversity/evenness_vector.qza

# Saved DistanceMatrix to: Beta_diversity/unweighted_unifrac_distance_matrix.qza
# Saved DistanceMatrix to: Beta_diversity/weighted_unifrac_distance_matrix.qza
# Saved DistanceMatrix to: Beta_diversity/jaccard_distance_matrix.qza
# Saved DistanceMatrix to: Beta_diversity/bray_curtis_distance_matrix.qza

# Saved PCoAResults to: Beta_diversity/unweighted_unifrac_pcoa_results.qza
# Saved PCoAResults to: Beta_diversity/weighted_unifrac_pcoa_results.qza
# Saved PCoAResults to: Beta_diversity/jaccard_pcoa_results.qza
# Saved PCoAResults to: Beta_diversity/bray_curtis_pcoa_results.qza

# Saved Visualization to: Beta_diversity/unweighted_unifrac_emperor.qzv
# Saved Visualization to: Beta_diversity/weighted_unifrac_emperor.qzv
# Saved Visualization to: Beta_diversity/jaccard_emperor.qzv
# Saved Visualization to: Beta_diversity/bray_curtis_emperor.qzv

# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then source activate ${QENV}; else conda activate ${QENV}; fi

#  5.2. 関数定義

#  5.3. feature-tableから最小リードデプスを取得
## unzip table.qza & convert feature table of biom format to tsv
echo -e "### Check read depth ###" >&2
unzip -q ${TAB} -d dat_biom
cmd1="biom convert -i dat_biom/*/data/feature-table.biom -o ./feature-table.tsv --to-tsv"
echo "# [CMND] Export feature table of biom format to tsv" >&2
echo ${cmd1} >&2 ; eval ${cmd1}

## get minimum depth value from feature table
DP=$(cat feature-table.tsv \
| awk -F"\t" '!/^#/{for(i=1;i<NF; i++)sum[i]+=$(i+1)}/^#OTU/{for(i=1; i<NF; i++) hd[i]=$(i+1)} \
END{for(i=1;i<=length(sum);i++)print hd[i]":"sum[i]}')
MINDP=$(echo ${DP[*]} | tr ' ' '\n' | cut -f2 -d":" | sort -n | head -1)
# echo ${DP[@]} | tr ' ' '\n' >&2
echo "[INFO] Minimum depth: ${MINDP}" | tee mindp.txt >&2
rm -r dat_biom feature-table.tsv

#  5.4. レアファクションカーブ [qiime diversity alpha-rarefaction] 
## NOTE: observed_features / faith_pd  : はalpha diversityは出さないのか? 
echo -e "### qiime diversity alpha-rarefaction ### " >&2
## arguments check: 出力ディレクトリ
if [[ -d "${OUTA}" ]]; then echo "[WARNING] ${OUTA} was already exists. The output files may be overwritten." ; else mkdir -p "${OUTA}"; fi 
if [[ -d "${OUTV}" ]]; then echo "[WARNING] ${OUTV} was already exists. The output files may be overwritten." ; else mkdir -p "${OUTV}"; fi 

## alpha rarfaction  with metadata (observed_otus -> observed_features)
cmd2="qiime diversity alpha-rarefaction --i-table ${TAB} --i-phylogeny ${TRE} \
--p-max-depth ${MINDP} --p-metrics simpson --p-metrics shannon --p-metrics observed_features --p-metrics faith_pd --p-metrics chao1 \
--m-metadata-file ${META} --o-visualization ${OUTAST}"
## alpha rarfaction withouut metadata
cmd3="qiime diversity alpha-rarefaction --i-table ${TAB} --i-phylogeny ${TRE} \
--p-max-depth ${MINDP} --p-metrics simpson --p-metrics shannon --p-metrics observed_features --p-metrics faith_pd --p-metrics chao1 \
--o-visualization ${OUTASD}"

if [[ -f "${META}" ]] ; then
  echo "# [CMND] 'qiime diversity alpha-rarefaction' with meta data." >&2
  echo ${cmd2} >&2 ; eval ${cmd2}
  echo "# [CMND] 'qiime diversity alpha-rarefaction' without meta data."  >&2
  echo ${cmd3} >&2 ; eval ${cmd3}
else 
  echo "# [CMND] 'qiime diversity alpha-rarefaction' without meta data." >&2
  echo ${cmd3} >&2 ; eval ${cmd3}
fi

## 出力ファイルがなければ終了
if [[ ! -f "${OUTAST}" || ! -f "${OUTASD}" ]]; then  echo "[ERROR] Rarefaction curves were not output." >&2 ; exit 1 ; fi

#  5.5. alpha diversity 比較 & クラスカルウォリス検定 [qiime diversity alpha-group-significance]
## NOTE: qzvのファイル名変更すべき vectorじゃない。　${i}_significance.qzv
for i in ${ALP[@]}; do
## arguments 
  va="${OUTA}/${i}_vector.qza"
  vz="${OUTV}/${i}_vector.qzv"
  echo -e "[INFO] alpha-diversity measure | alpha-diversity | alpha-group-significance   [ ${i} | ${va} | ${vz} ]"  >&2
## alpha diversity
  echo "# [CMND] qiime diversity alpha [ ${i} ]" >&2
  cmd4="qiime diversity alpha --i-table ${TAB} --p-metric ${i} --o-alpha-diversity ${va}"
  echo ${cmd4} >&2 ; eval ${cmd4}

## alpha diversity significance
  echo "# [CMND] qiime diversity alpha-group-significance [ ${i} ]" >&2
  cmd5="qiime diversity alpha-group-significance --i-alpha-diversity ${va} --m-metadata-file ${META} --o-visualization ${vz}"
  echo ${cmd5} >&2 ; eval ${cmd5}

done

## 出力ファイルがなければ終了
if [[ ! -f "${va}" || ! -f "${vz}" ]]; then  echo "[ERROR] Kruskal-Wallis test was not drawn." >&2 ; exit 1 ; fi

#  5.6. Beta diversity [ qiime diversity core-metrics-phylogenetic ]
## NOTE: --output-dirがすでにある場合エラー, 個別に出力指定
 echo -e "# [CMND] qiime diversity core-metrics-phylogenetic " >&2
 cmd6="qiime diversity core-metrics-phylogenetic \
 --i-phylogeny ${TRE} \
 --i-table ${TAB} \
 --m-metadata-file ${META} \
 --p-sampling-depth ${MINDP} \
 --o-rarefied-table ${OUTA}/rarefied_table.qza \
 --o-faith-pd-vector ${OUTA}/faith_pd_vector.qza \
 --o-observed-features-vector ${OUTA}/observed_features_vector.qza \
 --o-shannon-vector ${OUTA}/shannon_vector.qza \
 --o-evenness-vector ${OUTA}/evenness_vector.qza \
 --o-unweighted-unifrac-distance-matrix ${OUTA}/unweighted_unifrac_distance_matrix.qza \
 --o-weighted-unifrac-distance-matrix ${OUTA}/weighted_unifrac_distance_matrix.qza \
 --o-jaccard-distance-matrix ${OUTA}/jaccard_distance_matrix.qza \
 --o-bray-curtis-distance-matrix ${OUTA}/bray_curtis_distance_matrix.qza \
 --o-unweighted-unifrac-pcoa-results ${OUTA}/unweighted_unifrac_pcoa_results.qza \
 --o-weighted-unifrac-pcoa-results ${OUTA}/weighted_unifrac_pcoa_results.qza \
 --o-jaccard-pcoa-results ${OUTA}/jaccard_pcoa_results.qza \
 --o-bray-curtis-pcoa-results ${OUTA}/bray_curtis_pcoa_results.qza \
 --o-unweighted-unifrac-emperor ${OUTV}/unweighted_unifrac_emperor.qzv \
 --o-weighted-unifrac-emperor ${OUTV}/weighted_unifrac_emperor.qzv \
 --o-jaccard-emperor ${OUTV}/jaccard_emperor.qzv \
 --o-bray-curtis-emperor ${OUTV}/bray_curtis_emperor.qzv"
 echo ${cmd6} >&2 ; eval ${cmd6}

 echo "[INFO] Results of core-metrics-phylogenetic qza" >&2 
 echo "[INFO] Results of core-metrics-phylogenetic qzv" >&2 

#  5.7. Beta-diversity per SampleType [qiime diversity beta-group-significance]
 echo -e "### qiime diversity beta-group-significance ### "
## arguments
 BDMATS=(unweighted_unifrac_distance_matrix.qza weighted_unifrac_distance_matrix.qza bray_curtis_distance_matrix.qza)
 st=( $(seq 1 ${NST}) )
## beta-group-significance
for bd in ${BDMATS[@]}; do
  INMAT=${OUTA}/${bd}
  for j in ${st[@]}; do
    METACL=$(head -1 ${META} | cut -f"$(($j+1))")
    OUTBSV=$(echo ${OUTV}/${bd/_distance_matrix.qza/}_anosim_${METACL}.qzv)
    ## Input/Output
    echo -e "# [INFO] Distance measure: [${bd}] | Column_of_Metadata:[${METACL}] | Output: [${OUTBSV}]"  >&2
    ## beta-group-significance
    echo "# [CMND] qiime diversity beta-group-significance " >&2
    cmd7="qiime diversity beta-group-significance --i-distance-matrix ${INMAT} \
    --m-metadata-file ${META} --m-metadata-column ${METACL} \
    --p-method anosim --p-pairwise \
    --o-visualization ${OUTBSV} "
    echo ${cmd7} >&2 ; eval ${cmd7}
  done    
done

#  5.8.  Export tsv
function unqza_div () {
  # unzip -> data path -> extract data_frame -> exporeted_dirに保存
  # USAGE: unqza_div diversity_tsv $SHN $CHA $SMP $PCOU $PCOW $PCOB
  EXPORTD=$1; SHN=$2; CHA=$3; SMP=$4; PCOU=$5; PCOW=$6; PCOB=$7

  TEMP_SHN=$(mktemp -d)
  TEMP_CHA=$(mktemp -d)
  TEMP_SMP=$(mktemp -d)
  TEMP_PCOU=$(mktemp -d)
  TEMP_PCOW=$(mktemp -d)
  TEMP_PCOB=$(mktemp -d)
  trap "rm -rf $TEMP_SHN $TEMP_CHA $TEMP_SMP $TEMP_PCOU $TEMP_PCOW $TEMP_PCOB" EXIT

  unzip -q $SHN -d ${TEMP_SHN}
  unzip -q $CHA -d ${TEMP_CHA}
  unzip -q $SMP -d ${TEMP_SMP}
  unzip -q $PCOU -d ${TEMP_PCOU}
  unzip -q $PCOW -d ${TEMP_PCOW}
  unzip -q $PCOB -d ${TEMP_PCOB}

  cp ${TEMP_SHN}/*/data/alpha-diversity.tsv ${EXPORTD}/shannon_vector.tsv
  cp ${TEMP_CHA}/*/data/alpha-diversity.tsv ${EXPORTD}/chao1_vector.tsv
  cp ${TEMP_SMP}/*/data/alpha-diversity.tsv ${EXPORTD}/simpson_vector.tsv

  # data frame extraction from PCoA results
  PCOUDAT=$TEMP_PCOU/*/data/ordination.txt
  cat $PCOUDAT | awk -F"\n" '/^Site/,/^$/ {print}' \
  | grep -v "^Site" | grep -v "^$" > ${EXPORTD}/unweighted_unifrac_pcoa_results.tsv
  cat $PCOUDAT | awk -F"\n" '/^Proportion explained/,/^$/' \
  | grep -v "Proportion explained" | grep -v "^$" > ${EXPORTD}/unweighted_unifrac_pcoa_pe.txt

  PCOWDAT=$TEMP_PCOW/*/data/ordination.txt
  cat $PCOWDAT | awk -F"\n" '/^Site/,/^$/ {print}' \
  | grep -v "^Site" | grep -v "^$" > ${EXPORTD}/weighted_unifrac_pcoa_results.tsv
  cat $PCOWDAT | awk -F"\n" '/^Proportion explained/,/^$/' \
  | grep -v "Proportion explained" | grep -v "^$" > ${EXPORTD}/weighted_unifrac_pcoa_pe.txt

  PCOBDAT=$TEMP_PCOB/*/data/ordination.txt
  cat $PCOBDAT | awk -F"\n" '/^Site/,/^$/ {print}' \
  | grep -v "^Site" | grep -v "^$" > ${EXPORTD}/bray_curtis_pcoa_results.tsv 
  cat $PCOBDAT | awk -F"\n" '/^Proportion explained/,/^$/' \
  | grep -v "Proportion explained" | grep -v "^$" > ${EXPORTD}/bray_curtis_pcoa_pe.txt

}
SHN=${OUTA}/shannon_vector.qza
CHA=${OUTA}/chao1_vector.qza
SMP=${OUTA}/simpson_vector.qza
PCOU=${OUTA}/unweighted_unifrac_pcoa_results.qza
PCOW=${OUTA}/weighted_unifrac_pcoa_results.qza
PCOB=${OUTA}/bray_curtis_pcoa_results.qza
mkdir -p ${OUTT}
unqza_div ${OUTT} ${SHN} ${CHA} ${SMP} ${PCOU} ${PCOW} ${PCOB}

#  5.9. HeatMap
## biom形式のfeature table    qiime feature-table filter-features
echo -e "# [CMND] qiime feature-table filter-features" >&2
cmd8="qiime feature-table filter-features --i-table ${TAB} --m-metadata-file ${TAX} --o-filtered-table ${OUTA}/id-filtered-table.qza"
echo ${cmd8} >&2 ; eval ${cmd8}

## arguments
LEV=(2 3 4 5 6 7)
clm='ward'
st=($(seq 1 $NST))

## heat map with metadata for all taxonomic rank
for i in ${LEV[@]}; do 
  out="${OUTA}/table-l${i}.qza" 
  echo -e "# [CMND] qiime taxa collapse  [Input: id-filtered-table.qza | Output: ${out}]" >&2
  cmd9="qiime taxa collapse --i-table ${OUTA}/id-filtered-table.qza --i-taxonomy ${TAX} --p-level ${i} --o-collapsed-table ${out}"
  echo ${cmd9} >&2 ; eval ${cmd9}

  for j in ${st[@]}; do
    outheat="${OUTV}/heatmap_l${i}_SampleType${j}.qzv"
    METACL=$(head -1 ${META} | cut -f"$(($j+1))")
    echo -e "# [CMND] qiime feature-table heatmap [Input:${out} | Sample_type:${METACL} | Output: ${outheat} ]" >&2
    cmd10="qiime feature-table heatmap --i-table ${out}  \
    --m-sample-metadata-file ${META} --m-sample-metadata-column ${METACL} --o-visualization ${outheat} \
    --p-normalize --p-method ${clm} --p-color-scheme RdYlBu_r"
    echo ${cmd10} >&2 ; eval ${cmd10}
  done    
done

exit 0