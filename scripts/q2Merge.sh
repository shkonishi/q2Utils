#!/bin/bash
VERSION=0.0.231124
AUTHOR=SHOGO_KONISHI
CMDNAME=$(basename $0)

### Contents: Merge taxonomy and feature table ###
# 1. ドキュメント
#  1.1. ヘルプの表示 
#  1.2. 使用例の表示
# 2. オプション引数の処理
#  2.1. オプション引数の入力
#  2.2. オプション引数の判定およびデフォルト値の指定
# 3. コマンドライン引数の処理
# 4. プログラムに渡す引数の一覧 
# 5. qiime2パイプライン実行 
#  5.1. qiime2起動
#  5.2. 関数定義 
#  5.3. qza ファイルを一時ディレクトリに展開
#  5.4. 出力ディレクトリ及び一時ディレクトリ作成
#  5.5. ASVのラベル変更
#  5.6. feature-tableのフィルタリング
#  5.7. フィルタ後のASV, feature-table, taxonomyをqzaに変換
#  5.8. taxonomyとfeature-tableをマージ
#  5.9. taxonomy rankごとに集計
###


# 1. ドキュメント
#  1.1. ヘルプの表示
function print_doc() {
cat << EOS
使用法:
    $CMDNAME [オプション] 

用語の定義およびこのプログラム中で使用されるデフォルトファイル名:
    ASV配列         Denoisingされた配列 [repset.qza]
    feature-table   検体に含まれるASVのリードカウントテーブル. [table.qza]
    taxonomy        ASVの系統推定結果 qiime feature-classifierの出力 [taxonomy.qza]
    系統組成表      taxonomyデータとfeature-tableを結合したもの [taxonomy_cnt.tsv]

説明:
    このプログラムではqiime2が出力したfeature-table, taxonomy, 及びASV配列を以下のように編集します。
      - feature-table、taxonomy及びASV配列を最大リード数でフィルタリング
      - フィルタリング後のfeature-table、taxonomy及びASV配列をqzaに再変換(qiime2を使用した二次解析に使用)
      - フィルタリング後のfeature-table、taxonomy及びASV配列内のASVラベル(ハッシュ値)を変更(R等を使用した二次解析に使用)
        - フィルタリング後のfeature-tableとtaxonomyをマージ
        - 分類階層ごとのカウントテーブルに要約

    入力ファイルはオプション引数としてfeature-table[table.qza]、ASV配列[repset.qza]、及びtaxonomyデータ[taxonomy.qza]の全てを指定してください。
    いずれもqza形式で指定します。編集後の出力ファイルは全てtsv形式で出力フォルダに書き出されます。
    NOTE:qiime feature-table filter-featuresを使用すればfeature-tableのフィルタはできるらしい。

オプション: 
  -e    conda環境変数パス[default: ${HOME}/miniconda3/etc/profile.d/conda.sh ]
  -q    qiime2環境名[default: qiime2-2022.2 ]
  -t    feature-table [default: table.qza]
  -s    ASV配列 [default: repset.qza]
  -x    taxonomy [default: taxonomy.qza]
  -n    feature-tableとASV配列から、最大読み取り回数がn回以下の配列を削除 [default: 0 ] 
  -o    出力ディレクトリ名[default: taxonomy_output ]
  -p    出力ファイルプレフィックス[default: otu]
  -h    ヘルプドキュメントの表示

使用例: 
    $CMDNAME -t table.qza -s repset.qza -x taxonomy.qza         # ASV及びfeature-tableとtaxonomyを結合
    $CMDNAME -n 3 -t table.qza -s repset.qza -x taxonomy.qza    # ASV及びfeature-tableのフィルタリング. 最大3カウントのASV除外

    CENV=\${HOME}/miniconda3/etc/profile.d/conda.sh
    QENV='qiime2-2022.2'
    $CMDNAME -e \$CENV -q \$QENV  -n 3 -o taxonomy_output -p otu -t table.qza -s repset.qza -x taxonomy.qza

EOS
}
if [[ "$#" = 0 ]]; then print_doc; exit 1 ; fi

# 1.2. エラー
function print_err () { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]:$*" >&2 ;  }


# 2. オプション引数の処理
#  2.1. オプション引数の入力
while getopts e:q:t:s:x:n:o:p:uvh OPT
do
  case $OPT in
    "e" ) CENV="$OPTARG";;
    "q" ) QENV="$OPTARG";;
    "t" ) TAB="$OPTARG";;
    "s" ) SEQ="$OPTARG";;
    "x" ) TAX="$OPTARG";;
    "n" ) DP="$OPTARG" ;;
    "o" ) OUTD="$OPTARG";;
    "p" ) OUTPFX="$OPTARG";;
    "u" ) FLG_u="TRUE" ;;
    "v" ) echo $VERSION; exit 1 ;;
    "h" ) print_doc ; exit 1 ;; 
    *)    print_doc ; exit 1;; 
    \? )  print_doc ; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

#  2.2. オプション引数の判定およびデフォルト値の指定
## conda環境変数ファイルの存在確認
if [[ -z "${CENV}" ]]; then CENV="${HOME}/miniconda3/etc/profile.d/conda.sh"; fi
if [[ ! -f "${CENV}" ]]; then print_err "[ERROR] The file for the conda environment variable cannot be found. ${CENV}" ; exit 1 ; fi

## qiime2環境の存在確認
if [[ -z "$QENV" ]]; then QENV='qiime2-2022.2'; fi
conda info --env | grep -q $QENV || { echo "[ERROR] There is no ${QENV} environment."  >&2 ; conda info --envs >&2 ; exit 1 ; }

## ASV配列, feature-tableの判定
if [[ -z "${SEQ}" || -z "${TAB}" || -z "${TAX}" ]]; then print_err "[ERROR] All options t/s/x must be selected."; exit 1 ; fi
if [[ ! -f ${SEQ} || ${SEQ##*.} != 'qza' ]] ; then print_err "[ERROR] The ASV sequence, ${SEQ}, does not exist or is not in qza format."  ; exit 1 ; fi
if [[ ! -f ${TAB} || ${TAB##*.} != 'qza' ]] ; then print_err "[ERROR] The ASV table ${TAB} does not exist or is not in qza format." ; exit 1 ; fi
if [[ ! -f ${TAX} || ${TAX##*.} != 'qza' ]] ; then print_err "[ERROR] The taxonomy table ${TAX} does not exist or is not in qza format." ; exit 1 ; fi

## その他オプション引数の判定とデフォルト値
### Filter with read-depth
if [[ -z "${DP}" ]]; then DP=0 ; fi
if [[ -n "${DP}" && ! "${DP}" =~ ^[0-9]+$  ]]; then print_err "[ERROR] ${DP} must be an integer." ; exit 1; fi

### Results directory
if [[ -z "${OUTD}" ]]; then OUTD='taxonomy_output' ; fi
if [[ -d "${OUTD}" ]]; then print_err "[ERROR] The ${OUTD} already exist."; exit 1 ; fi

## Output files
if [[ -z "${OUTPFX}" ]];then PFX='asv' ; fi
### フィルタ済みテキスト
OTT=${OUTD}/${PFX}_filtered_cnt.tsv
OTFA=${OUTD}/${PFX}_filtered_asv.fasta 
OTX=${OUTD}/${PFX}_filtered_tax.tsv
### フィルタ済みqza
OTTZ=${OUTD}/${PFX}_filtered_cnt.qza
OTFAZ=${OUTD}/${PFX}_filtered_asv.qza
OTXZ=${OUTD}/${PFX}_filtered_tax.qza

### リラベルテキスト
RTT=${OUTD}/${PFX}_relabel_cnt.tsv 
RTFA=${OUTD}/${PFX}_relabel_asv.fasta
RTX=${OUTD}/${PFX}_relabel_tax.tsv
MTT=${OUTD}/${PFX}_merged_cnt.tsv

# 3. コマンドライン引数の処理

# 4. プログラムに渡す引数の一覧
cat << EOS >&2

### Merge taxonomy into count data, ASV sequences, and ASV trees ###
conda environmental values :              [ ${CENV} ]
qiime2 environment :                      [ ${QENV} ]
Input taxonomy file path(qza):            [ ${TAX} ]
Input ASV table file path(qza):           [ ${TAB} ]
Input ASV file path(qza):                 [ ${SEQ} ]
A maximum read count of remove            [ ${DP} ]
Output directory:                         [ ${OUTD} ]

## Filter ## 
Output filtered count table:              [ ${OTT} ]
Output filtered count table(qza):         [ ${OTTZ} ]
Output filtered ASV sequence fasta:       [ ${OTFA} ]
Output filtered ASV sequence fasta(qza):  [ ${OTFAZ} ]
Output filtered taxonomy table:           [ ${OTX} ]
Output filtered taxonomy table(qza):      [ ${OTXZ} ]

## Relabel ##
Output re-labeled count table:            [ ${OTT} ]
Output re-labeled ASV sequence fasta:     [ ${OTFA} ]
Output re-labeled taxonomy table:         [ ${OTX} ]
Output merged count table:                [ ${MTT} ]

EOS

# 5. 系統組成表の編集
#  5.1. qiime2起動
source ${CENV}
if echo ${CENV} | grep -q "anaconda" ; then source activate ${QENV} ; else  conda activate ${QENV} ; fi

# 5.2. 関数定義 
## 5.2.1. 関数定義: qzaファイルの展開とテキストファイルの取り出し
function unqza () {
  local TTAX=$1; local TTAB=$2 ; local TSEQ=$3 ; local OUTT='exported_txt'; 
  TEMP_TAX=$(mktemp -d)
  TEMP_TAB=$(mktemp -d)
  TEMP_SEQ=$(mktemp -d)
  trap "rm -rf ${TEMP_TAX} ${TEMP_TAB} ${TEMP_SEQ}" EXIT

  # Make output directory
  if [[ -d "${OUTT}" ]];then
      echo -e "[WARNING] ${OUTT} already exists. The output files may be overwritten." >&2
  else 
      mkdir -p "${OUTT}"
  fi
  
  # Unzip taxonomy qza
  unzip -q ${TTAX} -d $TEMP_TAX
  TAXTSV="${TEMP_TAX}/*/data/taxonomy.tsv"
  if [[ ! -f $(echo $TAXTSV) ]] ; then 
      echo -e "[ERROR] The specified argument ${TTAX} may not be a taxonomy." >&2
      exit 1 
  else 
      echo -e "[INFO] The taxonomy data unzipped to temporary directory.  ${TAXTSV}" >&2
      mv ${TAXTSV} ${OUTT}
  fi
  # Unzip feature-table qza
  unzip -q ${TTAB} -d ${TEMP_TAB}
  BIOME="${TEMP_TAB}/*/data/feature-table.biom" 
  FTTSV=${TEMP_TAB}/feature-table.tsv
  biom convert -i ${BIOME} -o ${FTTSV} --to-tsv 
  if [[ ! -f $(echo ${BIOME}) ]] ; then
      echo -e "[ERROR] ${TAB} may not be a feature table. " >&2
      exit 1
  else 
    echo -e "[INFO] The feature table data unzipped to temporary directory.  ${BIOME}" >&2
    echo -e "[INFO] The feature table data as biom convert to tsv.  ${FTTSV} " >&2
    mv ${FTTSV} ${OUTT}
  fi  
  # Unzip ASV fasta qza
  unzip -q ${TSEQ} -d ${TEMP_SEQ} 
  ASVFA="${TEMP_SEQ}/*/data/dna-sequences.fasta" 
  if [[ ! -f $(echo ${ASVFA}) ]] ; then
    echo -e "[ERROR] ${SEQ} may not be a ASV fasta. " >&2
    exit 1
  else 
    echo -e "[INFO] The ASV fasta unzipped to temporary directory.  ${ASVFA}" >&2
    mv ${ASVFA} ${OUTT}
  fi 
}

# 5.2.2. 関数定義: relabel ラベル変更後のファイルはqiimeに読み込めない
function relabel () {
  local CNT=$1 ; local ASV=$2 ; local TAX=$3  # 変更前
  local RLCNT=$4 ; local RLASV=$5; local RLTAX=$6 # 変更後
  
  # ASVのハッシュ値とOTUの対応表. この段階でASV_IDの同一性の確認は取れているものとする
  cut -f1 ${CNT} | grep -v "^#" | awk '{print $1"\t" "ASV" NR}' > asv2otu.tsv
  ls asv2otu.tsv > /dev/null 2>&1 || { echo -e "[ERROR] There is not ASV_ID corresponding table." >&2 ; }

  # ヘッダ行抽出(biom形式のfeature-tableにはコメント行が2行あることに注意)
  # taxonomyを再度読み込む場合ヘッダ行は変えては駄目なのだが(['Feature ID', 'Taxon'])、ここでは変更している
  grep -q "^#OTU ID" ${CNT} || { echo "[ERROR] The feature-table format may be invalid."  >&2 ; exit 1;  }
  grep "^#OTU ID" ${CNT} | sed -e "s/^#OTU ID/ASV_ID/"  > ${RLCNT}
  head -1 ${TAX} | sed -e "s/^Feature ID/ASV_ID/" > ${RLTAX}

  # ラベル置換して結合
  paste asv2otu.tsv <(grep -v "^#" ${CNT}) | awk -F"\t" '{if($1==$3){print}}' | cut -f2,4- >> ${RLCNT} # feature-tableのリラベル
  paste asv2otu.tsv <(cat ${ASV} | awk '/^>/ { printf("%s", n $0"\t"); n = "" }!/^>/ { printf "%s", $0; n = "\n" } END { printf "%s", n }'| sed -e "s/^>//" ) \
  | awk -F"\t" '{if($1==$3){ print ">"$2"\n"$4 }}'  >> ${RLASV} # ASV-fastaのリラベル
  paste asv2otu.tsv <(awk 'NR>1' ${TAX})  | awk -F"\t" '{if($1==$3){print}}' | cut -f2,4- >> ${RLTAX} # taxonomyのリラベル

}

# 5.2.3. 関数定義: Filter qzaをunzip抽出したfeature-table, fasta, taxonomyを入力とする
function filterOtu () {
  #　リード深度によるフィルタリング, -d 0 [DP=0]を指定した場合、
  local DP=$1
  local CNT=$2; local ASV=$3; local TAX=$4 # フィルタ前ファイル(入力)
  local PICKCNT=$5; local PICKASV=$6;  local PICKTAX=$7 # フィルタパスしたデータファイル(出力)
  # # test
  # filterOtu 3 feature-table.tsv dna-sequences.fasta taxonomy.tsv pick.cnt pick.asv pick.tax

  if [[ ${DP} > 1 ]]; then
    ## 最大リード数以下のOTUのIDを取得(ヘッダ行があることに注意)
    PICKOTU=($(cat ${CNT} | grep -v "^#" \
    | awk -F"\t" -v DP=${DP} '{for(i=2;i<=NF;i++){if(max[NR]==0){max[NR]=$i}else if(max[NR]<$i){max[NR]=$i}};if( max[NR]>DP)print $1;}' ))
    echo "[INFO] Pick ${#PICKOTU[@]} otus in $(( $(cat $CNT | grep -v "^#" | wc -l) )) " >&2

    ## フィルターパスしたカウントテーブルを保存
    head -2 ${CNT}| tail -1 > ${PICKCNT}
    awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print >> "'${PICKCNT}'"; }' \
      <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
      <( awk -F"\t" '$1!~/^#/' ${CNT} )

    ## フィルターパスしたASVを保存
    echo -n >| ${PICKASV}
    awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print ">"$1"\n"$2 >> "'${PICKASV}'"; }' \
    <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
    <( cat ${ASV} | awk '/^>/ { printf("%s", n $0"\t"); n = "" }!/^>/ { printf "%s", $0; n = "\n" } END { printf "%s", n }'| sed -e "s/^>//") 

    ## フィルターパスしたtaxonomyを保存
    head -1 ${TAX} > ${PICKTAX}
    awk 'NR==FNR{a[$1]=$1}NR!=FNR{if ($1 in a) print >> "'${PICKTAX}'"; }' \
    <( echo ${PICKOTU[@]}|tr ' ' '\n' ) \
    <( awk -F"\t" 'NR>1' ${TAX} ) 

  else
    cp ${CNT} ${PICKCNT}
    cp ${ASV} ${PICKASV}
    cp ${TAX} ${PICKTAX}
  fi
}

## 5.2.4. 関数定義: Combine taxonomy and feature-table <stdout>
function mtax () {
  # NOTE: feature-tableにはコメント行が2行存在、ただし最終行末尾に改行コードがないので行数はtaxonomyと一緒になっている
  # NOTE: ただしこのスクリプト内ではlabel変更の再にfeature-tableの1行目(# Constructed from biom file)は消去済み
  # NOTE: taxonomyとfeature-tableをpasteで結合した後にIDが同じことを確認してプリント,ID列をcutで除去
  # NOTE: PR2ではtaxonomy rank が8存在するので場合分けが必要だが、未対応
  local TTAX=$1; local TTAB=$2 ; local MTAB=$3

  # idの同一性チェック
  id_tab=($(grep -v "^#" ${TTAB} | awk -F"\t" '{print $1}'))
  id_tax=($(grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'))
  un1=($(echo ${id_tab[*]} ${id_tax[*]} | tr ' ' '\n' | sort | uniq -u))
  if [[ ${#un1} != '0' ]]; then echo "[ERROR] The file format of inputs was invalid. $1 and/or $2" >&2 ; fi

  # カウントデータからヘッダ行抽出
  if head -1 ${TTAB} | grep -e "^# Constructed from biom file$" > /dev/null ; then 
    HDTAB=($(tail -n +2 ${TTAB} | head -1 | cut -f2-))
  elif head -1 ${TTAB} | grep -e "^#OTU ID" > /dev/null ; then 
    HDTAB=($(grep -e "^#OTU ID" ${TTAB} | head -1 | cut -f2-))
  else
    HDTAB=( $(head -1 ${TTAB} | cut -f2-) )
  fi

  # taxonomyデータから分類階層のヘッダ行抽出 (7もしくは8の場合がある, また全てのOTUのrankが7もしくは8階層とは限らない)
  RANK=($(cut -f2 ${TTAX} | grep -v "Unassigned" | awk -F"; " 'BEGIN{OFS="\t"}NR>1{for(i=1;i<=NF;i++){sub("__.*$", "", $i)};print }' | sort | uniq | tail -1))
  NRANK=${#RANK[@]}
  HDC=($(echo 'ASV_ID' 'Confidence' ${RANK[@]} ${HDTAB[@]}))

  # ランク毎のテーブルに整形、未分類のセルには空文字を入れる(そのままだとカラム数が揃わない)
  # feature-tableにコメント行在りかなしかで分岐
  if [[ $NRANK == '7' ]]; then
    echo ${HDC[@]} | tr ' ' '\t' > $MTAB
    if grep -q "^#" ${TTAB} > /dev/null ; then
      paste <(tail -n +2 $TTAX | cut -f1,3) \
      <(tail -n +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}') \
      <(grep -v "^#" ${TTAB}) | awk -F"\t" '$1==$10' | cut -f1-9,11- >> $MTAB
    else 
      paste <(tail -n +2 $TTAX | cut -f1,3) \
      <(tail -n +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}') \
      <(tail -n +2 ${TTAB}) | awk -F"\t" '$1==$10' | cut -f1-9,11- >> $MTAB
    fi 
  elif [[ $NRANK == '8' ]]; then
    echo ${HDC[@]} | tr ' ' '\t' > $MTAB
    if grep -q "^#" ${TTAB} > /dev/null ; then
      paste <(tail -n +2 $TTAX | cut -f1,3) \
      <(tail -n +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8}') \
      <(grep -v "^#" ${TTAB}) | awk -F"\t" '$1==$11' | cut -f1-10,12- >> $MTAB
    else
      paste <(tail -n +2 $TTAX | cut -f1,3) \
      <(tail -n +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8}') \
      <(tail -n +2 ${TTAB}) | awk -F"\t" '$1==$11' | cut -f1-10,12- >> $MTAB
    fi
  else 
    echo -e "[ERROR] The file format of inputs was invalid." >&2
  fi

  # 出力ファイルチェック
  out_ncol=($(cat $MTAB | awk -F"\t" '{print NF}' | uniq)) 
  out_wl=$(cat $MTAB | wc -l); tax_wl=$(cat $TTAX | wc -l) ; tab_wl=$(cat $TTAB | wc -l)
  if [[ ${#out_ncol[@]} != '1' ]]; then 
    echo -e "[ERROR] The file format of inputs was invalid."  >&2
  fi
  if [[ ${out_wl} != ${tax_wl} || ${out_wl} != ${tab_wl} || ${tax_wl} != ${tab_wl} ]]; then
    echo -e "[ERROR] The output files format of inputs was invalid." >&2   
  fi  

}
## 5.2.5. 関数定義: Combine taxonomy and ASV <stdout>
function mtseq () {
  local TTAX=$1; local TSEQ=$2; local MSEQ=$3

  # idの同一性チェック
  id_seq=($(grep "^>" ${TSEQ} | sed 's/^>//'))
  id_tax=($(grep -v "^Feature" ${TTAX} | awk -F"\t" '{print $1}'))
  un1=($(echo ${id_tax[*]} ${id_seq[*]} | tr ' ' '\n' | sort | uniq -u)) 
  if [[ ${#un1} != '0' ]]; then echo "[ERROR] The file format of inputs was invalid. $1 and/or $2" >&2 ; fi

  # taxonomyデータからrankの配列を取り出す (7列もしくは8列の場合がある)
  RANK=($(cut -f2 ${TTAX} | awk -F"; " 'BEGIN{OFS="\t"}NR>1{for(i=1;i<=NF;i++){sub("__.*$", "", $i)};print }' | sort | uniq | tail -1))
  NRANK=${#RANK[@]}

  # ヘッダ行生成
  HDC=($(echo 'OTU_ID' 'Confidence' ${RANK[@]} 'Seq'))

  # taxonomyとASV配列をマージ
  # ランク毎のテーブルに整形、未分類のセルには空文字を入れる(そのままだとカラム数が揃わない)
  if [[ $NRANK == '7' ]]; then
    echo ${HDC[@]} | tr ' ' '\t' > $MSEQ
    paste <(tail -n +2 $TTAX | cut -f1,3) \
    <(tail -n +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7}') \
    <(cat ${TSEQ} | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}') | awk -F"\t" '$1==$10' | cut -f1-9,11- >> $MSEQ

  elif [[ $NRANK == '8' ]]; then
    echo ${HDC[@]} | tr ' ' '\t' > $MSEQ
    paste <(tail -n +2 $TTAX | cut -f1,3) \
    <(tail -n +2 ${TTAX} | cut -f2 | awk -F"; " -v nrank=$NRANK '{print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$8}') \
    <(cat ${TSEQ} | awk 'BEGIN{RS=">"; FS="\n"} NR>1 {print $1"\t"$2;}') | awk -F"\t" '$1==$11' | cut -f1-10,12- >> $MSEQ
  else
    echo -e "[ERROR] The file format of inputs was invalid." >&2
  fi

}

## 5.2.6. 関数定義: taxonomy rankごとに集計
function rankCnt () {
  # USAGE: rankCnt taxonomy_cnt.tsv outdir
  local OTT=$1 ; local OUTCNT=$2 
  if [[ ! -d ${OUTCNT} ]]; then echo "[ERROR] The ${OUTCNT} does not exists."; fi

  ## taxonomicランク列及びサンプル列を指定　
  ncol=$(head -1 ${OTT} | awk -F"\t" '{print NF}')
  ismp=$(head -1 ${OTT} | awk -F"\t" '{for(i=1; i<=NF; i++)if($i=="s")print i+1}')
  smps=($(head -1 ${OTT} | cut -f${ismp}-))
  ntax=($(seq 3 $((${ismp}-1))))
  nsmp=($(seq ${ismp} ${ncol}))

  ## taxonomic rankの判定　silva, greengene, pr2で場合分け
  rank1=$(head -1 ${OTT} | cut -f3); rank2=$(head -1 ${OTT} | cut -f4)
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
  abr=($(for i in ${rank[@]}; do echo ${i:0:1}; done))
  for k in ${!rank[@]}; do 
    rnk=${rank[$k]}
    in=${TEMP}/${rnk}.cnt
    out=${OUTCNT}/count_${abr[$k]}.tsv

    for x in ${smps[@]}; do 
      cat ${in} | awk -F"\t" -v x=${x} '$2==x{print $1"\t"$3}' \
      | sort -t$'\t' -k1,1 > ${TEMP}/${rnk}_${x}.tmp
    done
  
    n_temp=$(ls ${TEMP}/*.tmp | wc -l) # sample numbers
    slct=($(seq 2 2 $((${n_temp}*2)))) # column numbers of count data only
    echo -e "taxon "${smps[*]} | tr ' ' '\t' > ${out}
    paste ${TEMP}/${rnk}*.tmp | cut -f1,$(echo ${slct[@]}|tr ' ' ',')  >> ${out}
  done

}

# 5.3. qzaファイル展開
## exported_txt内に展開される
unqza ${TAX} ${TAB} ${SEQ}
FLTIN1=exported_txt/feature-table.tsv; FLTIN2=exported_txt/dna-sequences.fasta; FLTIN3=exported_txt/taxonomy.tsv

## 解凍済みテキストファイルの存在確認
if [[ ! -f ${FLTIN1} || ! -f ${FLTIN2} || ! -f ${FLTIN3} ]]; then print_err "No such file or directory." ; exit 1; fi

# 5.4. フィルタリング
mkdir -p ${OUTD}
filterOtu ${DP} ${FLTIN1} ${FLTIN2} ${FLTIN3} ${OTT} ${OTFA} ${OTX}

# 5.5 フィルタ後のASV, feature-table, taxonomyをqzaに変換
## ASVをfastaに変換後qzaに変換
echo "# [CMND] Import filtered ASV fasta " >&2
cmd1="qiime tools import --input-path ${OTFA} --output-path ${OTFAZ} --type 'FeatureData[Sequence]'"
echo ${cmd1} >&2 ; eval ${cmd1}

## taxonomyテーブルをqzaに変換
echo "# [CMND] Import filtered taxonomy table" >&2
cmd2="qiime tools import --input-path ${OTX} --output-path ${OTXZ} --type 'FeatureData[Taxonomy]'"
echo ${cmd2} >&2 ; eval ${cmd2}

## feature-table をbiomに変換後qzaに変換(biomファイルは一時ファイルに書出し後削除)
TEMP=$(mktemp -d) ; trap "rm -rf ${TEMP}" EXIT
TMPBIOM=${TEMP}/tmp_biom
echo "# [CMND] Import filtered feature table" >&2
cmd3="biom convert -i $OTT -o $TMPBIOM --to-hdf5"
cmd4="qiime tools import --input-path ${TMPBIOM} --output-path ${OTTZ} --type 'FeatureTable[Frequency]'"
echo ${cmd3} >&2 ; eval ${cmd3}
echo ${cmd4} >&2 ; eval ${cmd4}

# 5.6. ラベル変更(リードデプスによるフィルタはかけない)
relabel ${FLTIN1} ${FLTIN2} ${FLTIN3} ${RTT} ${RTFA} ${RTX}
if ls asv2otu.tsv > /dev/null ; then mv asv2otu.tsv ${OUTD}/. ; else echo "[ERROR] I cannot find a table of correspondence between ASV hash values and ASV labels."; exit 1; fi
echo "[INFO] Move asv2otu.tsv to ${OUTD} directory." >&2

# 5.8. Merge taxonomy and feature-table
MTT=${OUTD}/${PFX}_merged_cnt.tsv
mtax ${RTX} ${RTT} ${MTT}
ls ${MTT} > /dev/null 2>&1  || { echo "[ERROR] There is no file or directory named ${MTT}." ; exit 1; } 

# 5.9. taxonomy rankごとに集計
rankCnt $MTT $OUTD

exit 0
