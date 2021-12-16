#!/usr/bin/env bash

## Build 20211215-001-test

## 导入通用变量与函数
dir_shell=/ql/shell
. $dir_shell/share.sh

## 生成pt_pin清单
gen_pt_pin_array() {
    source $file_env
    ori_jdCookie=$JD_COOKIE
    ori_envs=$(eval echo "\$ori_jdCookie")
    ori_array=($(echo $ori_envs | sed 's/&/ /g'))
    local i j ori_pt_pin_temp
    for i in "${!ori_array[@]}"; do
        j=$((i + 1))
        ori_pt_pin_temp=$(echo ${ori_array[i]} | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|; s|%|\\\x|g}")
        ori_remark_name[i]="$(cat $dir_db/env.db | grep ${ori_array[i]} | grep remarks | perl -pe "{s|.*remarks\":\"([^\"]+).*|\1|g}" | tail -1)"
        [[ ! ${ori_remark_name[i]} ]] && ori_remark_name[i]="未备注"
        [[ $ori_pt_pin_temp == *\\x* ]] && ori_pt_pin[i]=$(printf $ori_pt_pin_temp) || ori_pt_pin[i]=$ori_pt_pin_temp
        ori_sn=$j
        ori_uesr_info[i]="序号 $j. 用户名：${ori_pt_pin[i]} 备注：${ori_remark_name[i]}"
    done
}

export_uesr_info(){
for i in $@; do
    for j in "${!ori_array[@]}"; do
        [[ ${ori_array[j]} == *$i* ]] && echo ${ori_uesr_info[j]}
    done
done
}

# Cookie 有效性检查
check_jd_ck(){
    local test_jd_cookie="$(curl -s --connect-timeout 5 --retry 3 --noproxy "*" "https://bean.m.jd.com/bean/signIndex.action" -H "cookie: $1")"
    [[ "$test_jd_cookie" ]] && return 0 || return 1
}

# 移除失效的 Cookie
remove_void_ck(){
    gen_pt_pin_array
    local tmp_jdCookie i j void_ck_num
    if [[ $jdCookie_1 ]]; then
        tmp_jdCookie=$jdCookie_1
    else
        source $file_env
        tmp_jdCookie=$JD_COOKIE
    fi
    local envs=$(eval echo "\$tmp_jdCookie")
    local array=($(echo $envs | sed 's/&/ /g'))
    local user_sum=${#array[*]}
    local test_connect="$(curl -I -s --connect-timeout 5 --retry 3 --noproxy "*" https://bean.m.jd.com/bean/signIndex.action -w %{http_code} | tail -n1)"
    if [ "$test_connect" -eq "302" ]; then
            echo -e ""
            tmp2=""
            tmp4=""
        for ((i = 0; i < $user_sum; i++)); do
            j=$((i + 1))
            check_jd_ck ${array[i]}
            if [[ $? = 0 ]]; then
                echo -e "# `export_uesr_info ${array[i]}` 状态正常"
                tmp1="$(export_uesr_info ${array[i]}) 状态正常<br>"
                tmp2="$tmp2$tmp1"
            elif [[ $? = 1 ]]; then
                echo -e "# `export_uesr_info ${array[i]}` 已失效"
                tmp3="$(export_uesr_info ${array[i]}) 已失效<br>"
                tmp4="$tmp4$tmp3"
            fi
        done
    else
        echo -e "# API 连接失败，跳过检测。"
    fi
    echo -e ""
}
remove_void_ck
notify_content="失效账号：<br>$tmp4<br>正常账号：<br>$tmp2"
notify "Cookie 状态通知" "$notify_content" >/dev/null 2>&1
wskey_scr=($(find /ql/scripts -type f -name *wskey*.py))
[[ $tmp4 ]] && [[ ${wskey_scr[0]} ]] && task ${wskey_scr[0]}