#!/usr/bin/env bash

## Build 20211219-003-test

## 导入通用变量与函数
dir_shell=/ql/shell
. $dir_shell/share.sh
. $dir_shell/api.sh

def_envs_tool(){
    for i in $@; do
        curl -s --noproxy "*" "http://0.0.0.0:5600/api/envs?searchValue=$i" -H "Authorization: Bearer $token"
    done
}

def_JD_COOKIE_json(){
    def_envs_tool JD_COOKIE | grep -Eo "\{\"value[^\}]+[^\}]+\}" | jq -r .$1
}

def_JD_WSCK_json(){
    def_envs_tool JD_WSCK | grep -Eo "\{\"value[^\}]+[^\}]+\}" | grep $1 | jq -r .$2
}

gen_basic_list(){
    ## 生成 json 值清单
    gen_basic_value(){
        for i in $@; do
            eval $i='($(def_JD_COOKIE_json $i))'
        done
    }

    value=()
    _id=()
    status=()
    remarks=()
    wskey_value=()
    wskey_id=()
    wskey_remarks=()
    gen_basic_value value _id status remarks
}

#青龙启用/禁用环境变量API
ql_process_env_api() {
    local currentTimeStamp=$(date +%s)
    local id=$1
    local process=$2
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
        if [[ $process = enable ]]; then
            echo -e "已启用"
        elif [[ $process = disable ]]; then
            echo -e "已禁用"
        fi
    else
        if [[ $process = enable ]]; then
            echo -e "已启用失败(${message})"
        elif [[ $process = disable ]]; then
            echo -e "已禁用失败(${message})"
        fi
    fi
}

## 生成pt_pin清单
gen_pt_pin_array() {
    local i j ori_pt_pin_temp
    for i in "${!value[@]}"; do
        ori_sn=$((i + 1))
        ori_pt_pin_temp=$(echo ${value[i]} | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|; s|%|\\\x|g}")
        [[ ! ${remarks[i]} ]] && remarks_name[i]="未备注" || remarks_name[i]="${remarks[i]}"
        [[  ${status[i]} = 0 ]] && current_status[i]="已启用" || current_status[i]="已禁用"
        [[ $ori_pt_pin_temp == *\\x* ]] && ori_pt_pin[i]=$(printf $ori_pt_pin_temp) || ori_pt_pin[i]=$ori_pt_pin_temp
        ori_uesr_info[i]="【$ori_sn】启用状态：${current_status[i]} ${ori_pt_pin[i]}; 备注：${remarks_name[i]}"
    done
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
    local test_jd_cookie="$(curl -s --connect-timeout 5 --retry 3 --noproxy "*" "https://bean.m.jd.com/bean/signIndex.action" -H "cookie: $1")"
    [[ "$test_jd_cookie" ]] && return 0 || return 1
}

# 批量检查 Cookie 有效性
verify_ck(){
    local test_connect="$(curl -I -s --connect-timeout 5 --retry 3 --noproxy "*" https://bean.m.jd.com/bean/signIndex.action -w %{http_code} | tail -n1)"
    for ((x = 1; x <=6; x++)); do eval tmp$x=""; done 
    if [ "$test_connect" -eq "302" ]; then
        echo ""
        for i in ${!value[@]}; do
            ori_sn[i]=$((i + 1))
            ori_pin[i]=$(eval echo "\${value[$i]}" | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}")
            #echo ${ori_pin[i]}
            ori_pt_pin_temp[i]=$(eval echo "\${value[$i]}" | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|; s|%|\\\x|g}")
            [[ ${ori_pt_pin_temp[i]} == *\\x* ]] && ori_pt_pin[i]=$(printf ${ori_pt_pin_temp[i]}) || ori_pt_pin[i]=${ori_pt_pin_temp[i]}
            [[ ${remarks[i]} ]] && remarks_name[i]="(${remarks[i]})" || remarks_name[i]="(未备注)"
            [[ ${status[i]} = 0 ]] && current_status[i]="已启用" || current_status[i]="已禁用"
            if [[ "$NOTIFY_SHOWNAMETYPE" ]]; then
                ori_uesr[i]="【${ori_sn[i]}】${ori_pt_pin[i]}"
            else
                ori_uesr[i]="【${ori_sn[i]}】${ori_pt_pin[i]}${remarks_name[i]}"
            fi
            wskey_value[i]="$(def_JD_WSCK_json ${ori_pin[i]} value)"
            wskey_id[i]="$(def_JD_WSCK_json ${ori_pin[i]} _id)"
            wskey_remarks[i]="$(def_JD_WSCK_json ${ori_pin[i]} remarks)"
            if [[ $NOTIFY_WSKEY_NO_EXIST = 1 ]] && [[ ! ${wskey_value[i]} ]]; then
                echo -e "${ori_uesr[i]}${remarks_name[i]} 未录入 JD_WSCK"
                tmp1="${ori_uesr[i]}\n"
                tmp2="$tmp2$tmp1"
            fi
            check_jd_ck ${value[i]}
            if [[ $? = 0 ]]; then
                ck_status[i]="正常"
                env_process="enable"
                tmp3="${ori_uesr[i]}\n"
                tmp4="$tmp4$tmp3"
            elif [[ $? = 1 ]]; then
                ck_status[i]="失效"
                env_process="disable"
                tmp5="${ori_uesr[i]}\n"
                tmp6="$tmp6$tmp5"
            fi
            ori_uesr_info[i]="【${ori_sn[i]}】${ori_pt_pin[i]}${remarks_name[i]} ${ck_status[i]}并$(ql_process_env_api ${_id[i]} $env_process)"
            echo -e "${ori_uesr_info[i]}"
        done
        [[ $NOTIFY_VALID_CK = 1 ]] && temp_valid_ck="失效账号：\n$tmp6\n正常账号：\n$tmp4" || temp_valid_ck="失效账号：\n$tmp6"
    else
        echo -e "# API 连接失败，跳过检测。"
    fi
    echo ""
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

gen_basic_list
echo -e ""
echo -e "# 开始检查账号有效性..."
verify_ck
if [[ $WSKEY_TO_CK = 1 ]]; then
    echo -e "# 正在搜索 wskey 转换脚本 ..."
    wskey_scr=($(find /ql/scripts -type f -name *wskey*.py))
    if [[ ${wskey_scr[0]} ]]; then
        if [[ $tmp6 ]]; then
            echo -e "# 检测到失效账号，开始执行 wskey 转换 ..."
            define_program $wskey_scr
            $which_program ${wskey_scr[0]}
            echo -e ""
            echo -e "# 重新检测 Cookie 有效性 ..."
            gen_basic_list > /dev/null 2>&1
            verify_ck
        fi
    else
        echo -e "# 未搜索到 wskey 转换脚本，跳过 wskey 转换 ..."
    fi
fi

[[ $NOTIFY_WSKEY_NO_EXIST = 1 ]] && temp_no_wsck="未录入 JD_WSCK 的账号：\n$tmp2\n"
notify_content="$temp_no_wsck$temp_valid_ck"

echo -e "$notify_content"
echo -e "# 推送通知..."
notify "Cookie 状态通知" "$notify_content" >/dev/null 2>&1
echo -e "# 执行完成。"

