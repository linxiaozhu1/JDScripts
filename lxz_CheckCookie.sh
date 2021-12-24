#!/usr/bin/env bash

## Build 20211224-001-test

## 导入通用变量与函数
dir_shell=/ql/shell
. $dir_shell/share.sh
. $dir_shell/api.sh

# 定义 json 数据查询工具
def_envs_tool(){
    for i in $@; do
        curl -s --noproxy "*" "http://0.0.0.0:5600/api/envs?searchValue=$i" -H "Authorization: Bearer $token"
    done
}

def_json_total(){
    def_envs_tool $1 | grep -Eo "\{\"value[^\}]+[^\}]+\}" | jq -r .$2
}

def_json(){
    def_envs_tool $1 | grep -Eo "\{\"value[^\}]+[^\}]+\}" | grep "$3" | jq -r .$2
}

def_json_value(){
    cat "$1" | perl -pe "{s|\n||g; s|\},|\}\n|g}" | grep -Eo "\{[^\}]+}" | grep -w "$3" | jq -r .$2
}

## 生成pt_pin清单
gen_pt_pin_array() {
    ## 生成 json 值清单
    gen_basic_value(){
        for i in $@; do
            if [[ $i = timestamp ]]; then
                eval $i="($(def_json_total JD_COOKIE $i | awk '{print $3,$2,$4,$5}' | perl -pe "{s| |-|g}"))"
            else
                eval $i='($(def_json_total JD_COOKIE $i | perl -pe "{s| ||g}"))'
            fi
        done
    }

    gen_basic_value value _id timestamp
    ori_sub=(${!value[@]})
    ori_sn=($(def_json JD_COOKIE value | awk '{print NR}'))
    pin=($(def_json_total JD_COOKIE value | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
    pt_pin=($(def_json_total JD_COOKIE value | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}" | awk 'BEGIN{for(i=0;i<10;i++)hex[i]=i;hex["A"]=hex["a"]=10;hex["B"]=hex["b"]=11;hex["C"]=hex["c"]=12;hex["D"]=hex["d"]=13;hex["E"]=hex["e"]=14;hex["F"]=hex["f"]=15;}{gsub(/\+/," ");i=$0;while(match(i,/%../)){;if(RSTART>1);printf"%s",substr(i,1,RSTART-1);printf"%c",hex[substr(i,RSTART+1,1)]*16+hex[substr(i,RSTART+2,1)];i=substr(i,RSTART+RLENGTH);}print i;}'))
}

#青龙启用/禁用环境变量API
ql_process_env_api() {
    local currentTimeStamp=$(date +%s)
    local id=$1
    local ck_status=$2
    [[ $2 = 0 ]] && process=enable
    [[ $2 = 1 ]] && process=disable
    local url="http://0.0.0.0:5600/api/envs/$process"

    local api=$(
        curl -s --noproxy "*" "$url?t=$currentTimeStamp" \
            -X 'PUT' \
            -H "Accept: application/json" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json;charset=UTF-8" \
            --data-raw "[\"$id\"]"
    )

    code=$(echo $api | jq -r .code)
    message=$(echo $api | jq -r .message)
    if [[ $code == 200 ]]; then
        if [[ $ck_status = 0 ]]; then
            echo -e "已重启"
        elif [[ $ck_status = 1 ]]; then
            echo -e "已禁用"
        fi
    else
        if [[ $ck_status = 0 ]]; then
            echo -e "已启用失败(${message})"
        elif [[ $ck_status = 1 ]]; then
            echo -e "已禁用失败(${message})"
        fi
    fi
}

## 打印账号信息
export_uesr_info(){
for i in $@; do
    for j in "${!value[@]}"; do
        [[ ${value[j]} == *$i* ]] && echo ${ori_uesr_info[j]}
    done
done
}

# Cookie 有效性检查
check_jd_ck(){
    local test_jd_cookie="$(curl -s --connect-timeout 20 --retry 3 --noproxy "*" "https://bean.m.jd.com/bean/signIndex.action" -H "cookie: $1")"
    [[ "$test_jd_cookie" ]] && return 0 || return 1
}

# 批量检查 Cookie 有效性
verify_ck(){
    for ((x = 1; x <=18; x++)); do eval tmp$x=""; done
    for i in ${!value[@]}; do
        remarks[$1]="$(def_json JD_COOKIE remarks "pin=${pin[$1]};" | head -1)"
        [[ ${remarks[$1]} ]] && remarks_name[$1]="(${remarks[$1]})" || remarks_name[$1]="(未备注)"
        [[ "$NOTIFY_SHOWNAMETYPE" ]] && full_name[$1]="【${ori_sn[$1]}】${pt_pin[$1]}" || full_name[$1]="【${ori_sn[$1]}】${pt_pin[$1]}${remarks_name[$1]}"
        status[i]="$(def_json JD_COOKIE status "pin=${pin[i]};" | head -1)"
        [[ ${status[i]} = 0 ]] && current_status[i]="已启用" || current_status[i]="已禁用"

        # JD_COOKIE 有效性检查
        local test_connect="$(curl -I -s --connect-timeout 20 --retry 3 --noproxy "*" https://bean.m.jd.com/bean/signIndex.action -w %{http_code} | tail -n1)"
        if [ "$test_connect" -eq "302" ]; then
            echo ""
            check_jd_ck ${value[i]}
            if [[ $? = 0 ]]; then
                ck_status[i]="0"
                if [[ ${ck_status[i]} = ${status[i]} ]]; then
                    ck_status_chinese[i]="正常"
                else
                    ck_status_chinese[i]="正常"
                    tmp1="${pt_pin[i]} "
                    tmp2="$tmp2$tmp1"
                fi
                tmp3="${full_name[i]}\n"
                tmp4="$tmp4$tmp3"
                tmp5="${pt_pin[i]} "
                tmp6="$tmp6$tmp5"
            elif [[ $? = 1 ]]; then
                ck_status[i]="1"
                if [[ ${ck_status[i]} = ${status[i]} ]]; then
                    ck_status_chinese[i]="失效"
                else
                    ck_status_chinese[i]="失效"
                    tmp7="${pt_pin[i]}\n"
                    tmp8="$tmp8$tmp7"
                fi
                tmp9="${full_name[i]}\n"
                tmp10="$tmp10$tmp9"
                tmp11="${pt_pin[i]} "
                tmp12="$tmp12$tmp11"
            fi
	
            if [[ $tmp2 ]] && [[ $NOTIFY_VALID_CK = 1 ]]; then
                tmp_content1="其中本次启用账号：$tmp2\n"
            elif [[ $tmp2 ]]; then
                tmp_content1="本次启用账号：$tmp2\n"
            fi
            [[ $tmp4 ]] && tmp_content2="正常账号：\n$tmp4\n"
            [[ $tmp8 ]] && tmp_content3="其中本次禁用账号：\n$tmp8\n"
            [[ $tmp10 ]] && tmp_content4="失效账号：\n$tmp10\n"
            if [[ $NOTIFY_VALID_CK = 1 ]]; then
                temp_valid_ck="$tmp_content4$tmp_content3$tmp_content2$tmp_content1"
            else
                temp_valid_ck="$tmp_content4$tmp_content3$tmp_content1"
            fi
            echo -n "【${ori_sn[i]}】${pt_pin[i]}${remarks_name[i]} ${ck_status_chinese[i]}"
            [[ ${ck_status[i]} != ${status[i]} ]] && echo -e "并$(ql_process_env_api ${_id[i]} ${ck_status[i]})" || echo -e ""
        else
            echo -e "# 【${ori_sn[i]}】${pt_pin[i]}${remarks_name[i]} 因 API 连接失败跳过检测。"
        fi

        # JD_WSCK 录入情况检查
        if [[ $NOTIFY_WSKEY_NO_EXIST = 1 || $NOTIFY_WSKEY_NO_EXIST = 2 ]]; then
            wskey_value[i]="$(def_json JD_WSCK value "pin=${pin[i]};" | head -1)"
            wskey_id[i]="$(def_json JD_WSCK _id "pin=${pin[i]};" | head -1)"
            wskey_remarks[i]="$(def_json JD_WSCK remarks "pin=${pin[i]};" | head -1)"
            if [[ ! ${wskey_value[i]} ]]; then
                echo -e "【${ori_sn[i]}】${pt_pin[i]}${remarks_name[i]} 未录入JD_WSCK"
                tmp13="${full_name[i]}\n"
                tmp14="$tmp14$tmp13"
            fi
            [[ $NOTIFY_WSKEY_NO_EXIST = 1 ]] && temp_no_wsck="未录入 JD_WSCK 的账号：\n$tmp14\n"
        fi

        # 账号剩余有效期检查
        if [[ $NOTIFY_VALID_TIME = 1 || $NOTIFY_VALID_TIME = 2 ]] && [[ ${ck_status_chinese[i]} = "正常" ]]; then
            sys_timestamp[i]=`date -d "$(echo ${timestamp[i]} | perl -pe '{s|-| |g}')" +%s`
            cur_sys_timestamp=`date '+%s'`
            total_validity_period=$((30*24*3600))
            remain_validity_period=$((total_validity_period-cur_sys_timestamp+sys_timestamp[i]))
            if [[ $remain_validity_period -ge 86400 ]]; then
                valid_time="$((remain_validity_period/86400))天"
            elif [[ $remain_validity_period -ge 3600 ]]; then
                valid_time="$((remain_validity_period/3600))小时"
            elif [[ $remain_validity_period -ge 60 ]]; then
                valid_time="$((remain_validity_period/60))分钟"
            elif [[ $remain_validity_period -ge 1 ]]; then
                valid_time="$remain_validity_period秒"
            fi
            echo -e "【${ori_sn[i]}】${pt_pin[i]}${remarks_name[i]} 剩余有效期$valid_time"
            tmp15="${full_name[i]} 剩余有效期$valid_time\n"
            tmp16="$tmp16$tmp15"
            [[ $NOTIFY_VALID_TIME = 1 ]] && temp_valid_time="\n预测账号有效期：\n$tmp16\n"
        fi

        # 生成 CK_WxPusherUid.json 模板
        if [[ $CK_WxPusherUid = 1 ]]; then
            [[ -d $dir_scripts/ccwav_QLScript2 ]] && CK_WxPusherUid_dir="$dir_scripts/ccwav_QLScript2" || CK_WxPusherUid_dir="$dir_scripts"
            [[ -f $CK_WxPusherUid_dir/CK_WxPusherUid.json ]] && Uid[i]="$(def_json_value "$CK_WxPusherUid_dir/CK_WxPusherUid.json" Uid "${pt_pin[i]}")" || Uid[i]=""
            tmp17=" {\n\t\"pin\": \"${pin[i]}\",\n\t\"备注\": \"${remarks[i]}\",\n\t\"pt_pin\": \"${pt_pin[i]}\",\n\t\"Uid\": \"${Uid[i]}\"\n }"
            tmp18="$tmp18,\n$tmp17"
            [[ $CK_WxPusherUid = 1 || $CK_WxPusherUid = 2 ]] && temp_CK_WxPusherUid="[\n$(echo $tmp18 | sed 's/^,\\n//')\n]"
        fi
    done
    temp_expired_ck="$(echo $tmp12 | perl -pe '{s| $||g}')"
    echo ""
}

#通知内容控制
sort_notify_content(){
    export_cache(){
        local value="$(eval echo \$$2)"
        if [[ $(cat $dir_scripts/$1 | grep $2) ]]; then
            sed -i "/$2/ s/\"[^\"]*\"/\"$value\"/g" $dir_scripts/$1
        else
            echo "$2=\"$value\"" >> $dir_scripts/$1
        fi
    }

    [[ $dir_scripts/CK_Cache ]] && . $dir_scripts/CK_Cache
    for i in $@; do
        if [[ "$(eval echo \$$i)" == "$(eval echo \$${i}_last)" ]]; then
            eval export ${i}_last="\$$i"
            eval "$i"=""
            [[ $i = temp_expired_ck ]] && echo "# 账号有效性检测结果与上次内容一致，本次不推送。" && temp_valid_ck=""
        elif [[ "$(eval echo \$$i)" != "$(eval echo \$"$i"_last)" ]]; then
            eval export ${i}_last="\$$i"
        fi
    done
    export_cache CK_Cache "$i"_last
}

## 选择python3还是node
define_program() {
    local first_param=$1
    if [[ $first_param == *.js ]]; then
        which_program="node"
    elif [[ $first_param == *.py ]]; then
        which_program="python3"
    elif [[ $first_param == *.sh ]]; then
        which_program="bash"
    elif [[ $first_param == *.ts ]]; then
        which_program="ts-node-transpile-only"
    else
        which_program=""
    fi
}

gen_pt_pin_array
echo -e ""
echo -n "# 开始检查账号有效性"
[[ $NOTIFY_VALID_TIME = 1 || $NOTIFY_VALID_TIME = 2 ]] && echo -e "，预测账号有效期谨供参考 ..." || echo -e " ..."
verify_ck
if [[ $WSKEY_TO_CK = 1 ]]; then
    echo -e "# 正在搜索 wskey 转换脚本 ..."
    wskey_scr=($(find /ql/scripts -type f -name *wskey*.py))
    if [[ ${wskey_scr[0]} ]]; then
        if [[ $tmp10 ]]; then
            echo -e "# 检测到失效账号，开始执行 wskey 转换 ..."
            define_program $wskey_scr
            $which_program ${wskey_scr[0]}
            echo -e ""
            echo -e "# 重新检查 Cookie 有效性 ..."
            gen_basic_list > /dev/null 2>&1
            verify_ck
        fi
    else
        echo -e "# 未搜索到 wskey 转换脚本，跳过 wskey 转换 ..."
    fi
fi

[[ $NOTIFY_SKIP_SAME_CONTENT = 1  ]] && sort_notify_content temp_expired_ck
notify_content="$temp_valid_ck$temp_no_wsck$temp_valid_time"

if [[ $notify_content ]]; then
    echo -e "$notify_content"
    [[ $CK_WxPusherUid = 1 ]] && echo -e $temp_CK_WxPusherUid > $CK_WxPusherUid_dir/CK_WxPusherUid.json
    [[ $CK_WxPusherUid = 2 ]] && echo -e $temp_CK_WxPusherUid > $CK_WxPusherUid_dir/CK_WxPusherUid_Sample.json
    echo -e "# 推送通知..."
    notify "Cookie 状态通知" "$notify_content" >/dev/null 2>&1
fi

echo -e "# 执行完成。"

