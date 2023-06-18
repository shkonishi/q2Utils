#!/bin/bash
VERSION=0.0.230617
AUTHOR=SHOGO_KONISHI
CMDNAME=`basename $0`

### Contents: Merge taxonomy and feature table ###
# 1. ドキュメント
#  1.1. ヘルプの表示 
#  1.2. 使用例の表示
# 2. オプション引数の処理
# 3. コマンドライン引数の処理
# 4. プログラムに渡す引数の一覧 
# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
#  5.2. 関数定義 
#  5.3. qza ファイルを一時ディレクトリに展開
#  5.4. データを結合
#  5.5. ASVの系統樹を作成
#  5.6. 一時ファイルの移動, 削除
###


# 1. ドキュメント
#  1.1. ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] <taxonomy.qza> 

用語の定義およびこのプログラム中で使用されるデフォルトファイル名:
    ASV配列     Denoisingされた配列 [repset.qza]
    ASVテーブル  検体に含まれるASVのリードカウントテーブル. qiime2的にはfeature-table [table.qza]
    taxonomy    ASVの系統推定結果 qiime feature-classifierの出力 [taxonomy.qza]
    系統組成表   taxonomyデータとASVテーブルを結合したもの [taxonomy_cnt.tsv]

説明:
    このプログラムはqiime2が出力したASVテーブルとtaxonomyデータの結合(系統組成表)、
    またはASV配列とtaxonomyデータの結合のいずれかまたは両方を実行します。
    もう一つの機能として、ノードラベルをtaxonomic-nameに変換したASV配列の系統樹を作成します。

    入力ファイルはコマンドライン引数にtaxonomyデータ[taxonomy.qza]を指定し、
    オプション引数としてASVテーブル[table.qza]またはASV配列[repset.qza]のいずれかまたは両方を指定してください。
    いずれもqza形式で指定します。結合された出力ファイルは[taxonomy_cnt.tsv|taxonomy_asv.tsv]として、
    tsv形式で書き出されます。

    ASV配列の系統樹を作成する場合、uオプションを指定することで、系統アサインされなかったASVは除去できます。
    qiime2の出力するnewick形式のASVツリーでは、各ノードがASVのハッシュ値となっているため上記の系統組成表を基にして
    taxonomic-nameに変換して出力します。
    
オプション: 
  -e    conda環境変数パス[default: ${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2021.8 ]
  -t    ASVテーブル [default: table.qza]
  -s    ASV配列 [default: repset.qza]
  -n    ASVテーブルとASV配列から、最大読み取り回数がn回以下の配列を削除 [default: 0 ] 
        qiime feature-table filter-featuresは使用していない
  -o    出力ディレクトリ名[default: Results]
  -p    出力ファイルプレフィックス[default: otu]
  -h    ヘルプドキュメントの表示
EOS
}
#  1.2. 使用例の表示
function print_usg() {
cat << EOS
使用例: 
    $CMDNAME -t table.qza -s repset.qza taxonomy.qza         # ASV及びfeature-tableとtaxonomyを結合
    $CMDNAME -n 3 -t table.qza -s repset.qza taxonomy.qza    # ASV及びfeature-tableのフィルタリング. 最大3カウントのASV除外

    CENV=\${HOME}/miniconda3/etc/profile.d/conda.sh
    QENV='qiime2-2021.8'
    $CMDNAME -e \$CENV -q \$QENV  -t table.qza -s repset.qza taxonomy.qza

EOS
}
if [[ "$#" = 0 ]]; then print_doc; print_usg; exit 1; fi


# 2. オプション引数の処理
#  2.1. オプション引数の入力
while getopts e:q:t:s:n:o:p:h OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;
    "t" ) VALUE_t="$OPTARG";;
    "s" ) VALUE_s="$OPTARG";;
    "n" ) VALUE_n="$OPTARG" ;;
    "o" ) VALUE_o="$OPTARG";;
    "p" ) VALUE_p="$OPTARG";;
    "u" ) FLG_u="TRUE" ;;
    "h" ) print_doc ; print_usg ; 
            exit 1 ;; 
    *) print_doc
        exit 1;; 
    \? ) print_doc ; print_usg
            exit 1 ;;
  esac
done
shift `expr $OPTIND - 1`

#  2.2. オプション引数の判定およびデフォルト値の指定
## conda環境変数ファイルの存在確認
if [[ -z "${CENV}" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; fi
if [[ ! -f "${CENV}" ]]; then
 echo "[ERROR] The file for the conda environment variable cannot be found. ${CENV}"
 print_usg
 exit 1
fi
## qiime2環境の存在確認
if [[ -z "${QENV}" ]]; then QENV="qiime2-2022.8"; fi
if conda info --envs | awk '!/^#/{print $1}'| grep -q "^${QENV}$" ; then
    :
else 
    echo "[ERROR] The conda environment ${QENV} was not found."
    conda info --envs
    print_usg
    exit 1
fi

## ASV配列, ASVテーブルの判定
if [[ -z "${VALUE_s}" || -z "${VALUE_t}" ]]; then echo "[ERROR] Both options t/s must be selected."; exit 1 ; fi
if [[ -n "${VALUE_s}" && -n "${VALUE_t}" ]]; then
    SEQ=${VALUE_s} ; TAB=${VALUE_t}
    if [[ ! -f ${SEQ} || ${SEQ##*.} != 'qza' ]] ; then 
        echo "[ERROR] The ASV sequence, ${SEQ}, does not exist or is not in qza format." 
        exit 1
    fi  
    if [[ ! -f ${TAB} || ${TAB##*.} != 'qza' ]] ; then 
        echo "[ERROR] The ASV table ${TAB} does not exist or is not in qza format." 
        exit 1
    fi

fi

## その他オプション引数の判定とデフォルト値
### Filter with read-depth
if [[ -z "${VALUE_n}" ]]; then 
  DP=0
elif [[ -n "${VALUE_n}" && "${VALUE_n}" =~ ^[0-9]+$  ]]; then
  DP=${VALUE_n}
else 
  echo -e "[ERROR] ${VALUE_n} is not number"
  exit 1
fi
### Results directory
if [[ -n "${VALUE_o}" && -d "${VALUE_o}" ]]; then 
  echo -e "[ERROR] The ${VALUE_o} already exist."; exit 1
elif [[ -n "${VALUE_o}" && ! -d "${VALUE_o}" ]]; then
  OUTD=${VALUE_o}
elif [[ -z ${VALUE_o} ]]; then
  OUTD='./Results' 
fi
## Output files
if [[ -z "${VALUE_p}" ]];then PFX='otu' ; else PFX=${VALUE_p} ; fi
OTT=${OUTD}/${PFX}_filtered_cnt.tsv
RTT=${OUTD}/${PFX}_removed_cnt.tsv 
OTF=${OUTD}/${PFX}_filtered_asv.tsv 
RTF=${OUTD}/${PFX}_removed_asv.tsv

# 3. コマンドライン引数の処理 
if [[ $# = 1 ]];then
  TAX=$1
  if [[ ! -f ${TAX} || ${TAX##*.} != 'qza' ]] ; then 
      echo "[ERROR] The taxonomy data ${TAX} does not exist or is not in qza format." ; exit 1
  fi   
else
    echo "[ERROR] Taxonomy data (qza format) is required as a command line argument." ;  print_usg; exit 1
fi

# 4. プログラムに渡す引数の一覧
cat << EOS >&2
### Merge taxonomy into count data, ASV sequences, and ASV trees ###
  conda environmental values :          [ ${CENV} ]
  qiime2 environment :                  [ ${QENV} ]
  Input taxonomy file path:             [ ${TAX} ]
  Input ASV table file path:            [ ${TAB} ]
  Input ASV file path:                  [ ${SEQ} ]
  A maximum read count of remove        [ ${DP} ]
  Output directory:                     [ ${OUTD} ]
  Output filtered count table:          [ ${OTT} ]
  Output removed taxonomy table:        [ ${RTT} ]
  Output filtered ASV sequence table:   [ ${OTF} ]
  Output removed ASV sequence table:    [ ${RTF} ]

EOS

# 5. 系統組成表の編集
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then 
 source activate ${QENV}
else 
 conda activate ${QENV} 
fi

# 5.2. 関数定義 
## 5.2.1. 関数定義: qzaファイルの展開
function unqza () {
  TTAX=$1; TTAB=$2 ; TSEQ=$3
  TEMP_TAX=$(mktemp -d)
  TEMP_TAB=$(mktemp -d)
  TEMP_SEQ=$(mktemp -d)
  trap "rm -rf ${TEMP_TAX} ${TEMP_TAB} ${TEMP_SEQ}" EXIT

  # output directory
  OUTT='exported_txt'; 
  if [[ -d "${OUTT}" ]];then
      echo "[WARNING] ${OUTT} already exists. The output files may be overwritten." >&2
  else 
      mkdir -p "${OUTT}"
  fi
  
  unzip -q ${TTAX} -d $TEMP_TAX
  TAXTSV="${TEMP_TAX}/*/data/taxonomy.tsv"
  if [[ ! -f $(echo $TAXTSV) ]] ; then 
      echo -e "[ERROR] The specified argument ${TTAX} may not be a taxonomy."
      exit 1 
  else 
      echo -e "[INFO] The taxonomy data unzipped to temporary directory.  ${TAXTSV}"
      mv ${TAXTSV} ${OUTT}
  fi

  unzip -q ${TTAB} -d ${TEMP_TAB}
  BIOME="${TEMP_TAB}/*/data/feature-table.biom" 
  FTTSV=${TEMP_TAB}/feature-table.tsv
  biom convert -i ${BIOME} -o ${FTTSV} --to-tsv 
  if [[ ! -f $(echo ${BIOME}) ]] ; then
      echo -e "[ERROR] ${TAB} may not be a feature table. "
      exit 1
  else 
    echo -e "[INFO] The feature table data unzipped to temporary directory.  ${BIOME}"
    echo -e "[INFO] The feature table data as biom convert to tsv.  ${FTTSV} "
    mv ${FTTSV} ${OUTT}
  fi  

  unzip -q ${TSEQ} -d ${TEMP_SEQ} 
  ASVFA="${TEMP_SEQ}/*/data/dna-sequences.fasta" 
  if [[ ! -f $(echo ${ASVFA}) ]] ; then
    echo -e "[ERROR] ${SEQ} may not be a ASV fasta. "
    exit 1
  else 
    echo -e "[INFO] The ASV fasta unzipped to temporary directory.  ${ASVFA}"
    mv ${ASVFA} ${OUTT}
  fi 

}

## 5.2.2. 関数定義: Combine taxonomy and feature-table <stdout>
function mtax () {
  # NOTE: feature-tableにはコメント行が2行存在、ただし最終行末尾に改行コードがないので行数はtaxonomyと一緒になっている
  # NOTE: ASV_ID列を削除せずにpasteし、ASV_IDが同一の場合出力したのちにwc -lで確認
  # NOTE: taxonomyとfeature-tableをpasteで結合した後にIDが同じことを確認してプリント,ID列をcutで除去
  # NOTE: PR2ではtaxonomy rank が8存在するので場合分けが必要
  # NOTE: 結果は標準出力なので、ID同一性チェックは関数の外で、行数変わっていないかで確認

  TTAX=$1; TTAB=$2 
  # カウントデータからヘッダ行抽出
  HD=(`grep "^#OTU ID" ${TTAB} | sed 's/^#OTU ID//'`)
  
  # taxonomyデータからrankの配列を取り出す (7列もしくは8列の場合がある)
  RANK=(`cut -f2 $TTAX | awk -F"; " '{if(NF==8){ \
  sub("_.*","",$1);sub("_.*","",$2);sub("_.*","",$3);sub("_.*","",$4); \
  sub("_.*","",$5); sub("_.*","",$6);sub("_.*","",$7); sub("_.*","",$8); \
  print $1" "$2" "$3" "$4" "$5" "$6" "$7" "$8;} \
  else if(NF==7){sub("_.*","",$1);sub("_.*","",$2);sub("_.*","",$3);sub("_.*","",$4); \
  sub("_.*","",$5); sub("_.*","",$6);sub("_.*","",$7); print $1" "$2" "$3" "$4" "$5" "$6" "$7;}}' | head -1`)

  # ヘッダ行作成,
  HDC=(`echo ASV_ID confidence ${RANK[@]} ${HD[@]}`)

  # idの同一性チェック(念の為)
  id_tab=(`grep -v "^#" ${TTAB} | awk -F"\t" '{print $1}'`)
  id_tax=(`grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'`)
  un1=(`echo ${id_tab[*]} ${id_tax[*]} | tr ' ' '\n' | sort | uniq -c | awk '{print $1 }' | uniq`) 

  # Merge 
  if [[ ${#un1[@]} == 1 && ${un1[@]} == 2 ]]; then

    NC=`cat ${TTAX} | cut -f2 | awk -F"; " '{print NF}' | sort -u | sort -nr | head -1`
    if [[ ${NC}==7 || ${NC}==8 ]]; then CTCOL=$(($NC+3)); else echo -e "[ERROR]"; exit 1; fi

    # ヘッダ行プリント
    echo ${HDC[@]} | tr ' ' '\t'
    # taxonomyとfeature-tableをマージした後、id列除去
    paste <(cat ${TTAX} | awk -F"\t" 'NR>1{print}' \
    | awk -F"\t" -v NC=${NC} '{split($2, arr, "; "); \
    if(NC==8){print $1"\t"$3"\t"arr[1]"\t"arr[2]"\t"arr[3]"\t"arr[4]"\t"arr[5]"\t"arr[6]"\t"arr[7]"\t"arr[8] ;} \
    else if(NC==7){print $1"\t"$3"\t"arr[1]"\t"arr[2]"\t"arr[3]"\t"arr[4]"\t"arr[5]"\t"arr[6]"\t"arr[7]}}') \
    <(cat ${TTAB} | awk 'NR>2') \
    | cut -f1-$(($CTCOL-1)),$(($CTCOL+1))- 
  else 
      echo "[ERROR] The file format of inputs was invalid."
  fi
}
## 5.2.3. 関数定義: Combine taxonomy and ASV <stdout>
function mtseq () {
    TTAX=$1; TSEQ=$2; 

    # taxonomyデータからrankの配列を取り出す (7列もしくは8列の場合がある)
    RANK=(`cut -f2 $TTAX | awk -F"; " '{if(NF==8){ \
    sub("_.*","",$1);sub("_.*","",$2);sub("_.*","",$3);sub("_.*","",$4); \
    sub("_.*","",$5); sub("_.*","",$6);sub("_.*","",$7); sub("_.*","",$8); \
    print $1" "$2" "$3" "$4" "$5" "$6" "$7" "$8;} \
    else if(NF==7){sub("_.*","",$1);sub("_.*","",$2);sub("_.*","",$3);sub("_.*","",$4); \
    sub("_.*","",$5); sub("_.*","",$6);sub("_.*","",$7); print $1" "$2" "$3" "$4" "$5" "$6" "$7;}}' | head -1`)

    # ヘッダ行作成
    HDC=(`echo ASV_ID confidence ${RANK[@]} Seq`)

    # idの同一性チェック(ファイル結合した後でid列除去しているのでいらないかも)
    id_tax=(`grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'`)
    id_seq=(`grep "^>" ${TSEQ} | sed 's/^>//'`)
    un=(`echo ${id_tax[*]} ${id_seq[*]} | tr ' ' '\n' | sort | uniq -c | awk '{print $1 }' | uniq`)

    # taxonomyとASV配列をマージ
    if [[ ${#un[@]} == 1 && ${un[@]} == 2 ]]; then
      NC=`cat ${TTAX} | cut -f2 | awk -F"; " '{print NF}' | sort -u | sort -nr | head -1`
      if [[ ${NC}==7 || ${NC}==8 ]]; then CTCOL=$(($NC+3)); else echo -e "[ERROR]"; exit 1; fi
      echo ${HDC[@]} | tr ' ' '\t'
      paste <(cat ${TTAX} | awk -F"\t" 'NR>1{print}' \
      | awk -F"\t" -v NC=${NC} '{split($2, arr, "; "); \
      if(NC==8){print $1"\t"$3"\t"arr[1]"\t"arr[2]"\t"arr[3]"\t"arr[4]"\t"arr[5]"\t"arr[6]"\t"arr[7]"\t"arr[8] ;} \
      else if(NC==7){print $1"\t"$3"\t"arr[1]"\t"arr[2]"\t"arr[3]"\t"arr[4]"\t"arr[5]"\t"arr[6]"\t"arr[7]}}') \
      <(cat ${TSEQ} | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}') \
      | cut -f1-$(($CTCOL-1)),$(($CTCOL+1))- 
    else 
        echo "[ERROR] The input file format was invalid."
    fi

}

## 5.2.4. 関数定義: Relabel ASV_ID to OTU , output file name asv2otu.tsv
function relabel () {
  MCNT=$1 ; MASV=$2 ; RLCNT=$3 ; RLASV=$4
  # ASVのハッシュ値とOTUの対応表. この段階でASV_IDの同一性の確認は取れているものとする
  cut -f1 ${MCNT} | awk 'NR>1{print $1"\t" "OTU" NR-1}' > asv2otu.tsv
  ls asv2otu.tsv > /dev/null 2>&1 || { echo -e "[ERROR] There is not ASV_ID corresponding table." ; }

  # ラベル置換
  head -1 ${MCNT} > ${RLCNT}
  head -1 ${MASV} > ${RLASV}
  paste asv2otu.tsv <(awk 'NR>1' ${MCNT}) | awk -F"\t" '{if($1==$3){print}}' | cut -f2,4- >> ${RLCNT}
  paste asv2otu.tsv <(awk 'NR>1' ${MASV}) | awk -F"\t" '{if($1==$3){print}}' | cut -f2,4- >> ${RLASV}

}

## 5.2.5. 関数定義: Filter
function filterOtu () {
  DP=$1; CNT=$2; ASV=$3;  PICKCNT=$4; RMCNT=$5; PICKASV=$6;  RMASV=$7

  if [[ ${DP} > 1 ]]; then
    ## 最大リード数以下のOTUのIDを取得(ヘッダ行があることに注意)
    PICKOTU=($(cut -f1,10- ${CNT} \
    | awk -F"\t" -v DP=${DP} 'NR>1{for(i=2;i<=NF;i++){if(max[NR]==0){max[NR]=$i}else if(max[NR]<$i){max[NR]=$i}};if( max[NR]>DP)print $1;}' ))
    
    ## フィルターパスしたカウントテーブルと除去したカウントテーブルを別々に保存
    head -1 ${CNT} > ${PICKCNT}
    head -1 ${CNT} > ${RMCNT}
    awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print >> "'${PICKCNT}'"; else print >> "'${RMCNT}'" }' \
      <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
      <( awk -F"\t" 'NR>1' ${CNT} )

    ## フィルターパスしたASVと除去したASVを別々に保存
    head -1 ${ASV} > ${PICKASV}
    head -1 ${ASV} > ${RMASV}
    awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print >> "'${PICKASV}'"; else print >> "'${RMASV}'"}' \
    <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
    <( awk -F"\t" 'NR>1' ${ASV} ) 

  else
    mv ${CNT} ${PICKCNT}
    mv ${ASV} ${PICKASV}
  fi
}

## 5.2.6. taxonomy rankごとに集計
function rankCnt () {
  # USAGE: taxcomp taxonomy_cnt.tsv outdir
  OTT=$1 ; OUTCNT=$2 
  if [[ -d ${OUTCNT} ]]; then echo "[WARNINGS] The ${OUTCNT} aleady exists."; else mkdir -p ${OUTCNT}; fi
  
  ## taxonomicランク列及びサンプル列を指定　
  ncol=`head -1 ${OTT} | awk -F"\t" '{print NF}'`
  ismp=10
  smps=(`head -1 ${OTT} | cut -f${ismp}-`)
  ntax=(`seq 3 $((${ismp}-1))`)
  nsmp=(`seq ${ismp} ${ncol}`)

  ## taxonomic rankの判定　silva, greengene, pr2で場合分け
  rank1=`head -1 ${OTT} | cut -f3`; rank2=`head -1 ${OTT} | cut -f4`
  if [[ $rank1 = 'd' && $rank2 = 'p' ]]; then
    rank=(domain phylum class order family genus species)
  elif [[ $rank1 = 'k' && $rank2 = 'p' ]]; then
    rank=(kingdom phylum class order family genus species)
  elif [[ $rank1 = 'd' && ! $rank2 = 'u' ]]; then
    rank=(domain supergroup phylum class order family genus species)
  fi

  ## 一時ディレクトリ作成
  TEMP=$(mktemp -d)
  trap 'rm -rf $TEMP' EXIT

  ## rank毎に行持ちデータフレームを作成し、要約
  for j in ${!ntax[@]}; do
    ptax=${ntax[$j]}; tax=${rank[$j]}
    for i in ${!nsmp[@]}; do
      psmp=${nsmp[$i]}; smp=${smps[$i]}
      cut -f${ptax},${psmp} ${OTT} | sed -e '1d' \
      | awk -F"\t" -v smp="${smp}" '{if($1==""){$1="Unassigned"}; arr[$1]+=$2}END{for(x in arr)print x"\t"smp"\t"arr[x]}'
    done > ${TEMP}/${tax}.cnt
  done

  ## 列持ちデータに変換
  abr=(`for i in ${rank[@]}; do echo ${i:0:1}; done`)
  for k in ${!rank[@]}; do 
    rnk=${rank[$k]}
    in=${TEMP}/${rnk}.cnt
    out=${OUTCNT}/count_${abr[$k]}.tsv

    for x in ${smps[@]}; do 
      cat ${in} | awk -F"\t" -v x=${x} '$2==x{print $1"\t"$3}' \
      | sort -t$'\t' -k1,1 > ${TEMP}/${rnk}_${x}.tmp
    done
  
    n_temp=`ls ${TEMP}/*.tmp | wc -l` # sample numbers
    slct=(`seq 2 2 $((${n_temp}*2))`) # column numbers of count data only
    echo -e "taxon "${smps[*]} | tr ' ' '\t' > ${out}
    paste ${TEMP}/${rnk}*.tmp | cut -f1,`echo ${slct[@]}|tr ' ' ','`  >> ${out}
  done

}

# 5.3. qzaファイル展開
## exported_txt内に展開される
unqza ${TAX} ${TAB} ${SEQ}

# 5.4. 
## 出力ディレクトリ及び一時ディレクトリ作成
mkdir -p ${OUTD}
TEMP=$(mktemp -d)
trap "rm -rf ${TEMP}" EXIT

## 5.5. ASVテーブル、ASV配列とtaxonomyを結合
mtax exported_txt/taxonomy.tsv exported_txt/feature-table.tsv > ${TEMP}/merged_cnt
mtseq exported_txt/taxonomy.tsv exported_txt/dna-sequences.fasta > ${TEMP}/merged_asv

# 5.6. ASVラベル変更
relabel ${TEMP}/merged_cnt ${TEMP}/merged_asv ${TEMP}/relavel_cnt ${TEMP}/relavel_asv
mv asv2otu.tsv ${OUTD}/.

# 5.7. ASVテーブルフィルタリング
filterOtu ${DP} ${TEMP}/relavel_cnt ${TEMP}/relavel_asv ${OTT} ${RTT} ${OTF} ${RTF}

# 5.8. taxonomy rankごとに集計
rankCnt ${OTT} ${OUTD}
