import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:project/main_tabview/main_tabview.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<String> selectedHistorys = [];
  bool selectAll = false;

  Future<void> _removeSelectedHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    // ยืนยันการลบ
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ยืนยันการลบ'),
        content: Text('คุณต้องการลบประวัติที่เลือกใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('ยืนยัน'),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      final historyRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.email)
          .collection('historys');

      for (String historyId in selectedHistorys) {
        try {
          await historyRef.doc(historyId).delete();
        } catch (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("เกิดข้อผิดพลาดในการลบประวัติ: $error")),
          );
        }
      }

      setState(() {
        selectedHistorys.clear();
        selectAll = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ลบประวัติที่เลือกเรียบร้อยแล้ว")),
      );
    }
  }

  void _toggleSelection(String historyId) {
    setState(() {
      if (selectedHistorys.contains(historyId)) {
        selectedHistorys.remove(historyId);
      } else {
        selectedHistorys.add(historyId);
      }
    });
  }

  void _toggleSelectAll(List<String> allHistoryIds) {
    setState(() {
      if (selectAll) {
        selectedHistorys.clear();
      } else {
        selectedHistorys = List.from(allHistoryIds);
      }
      selectAll = !selectAll;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("ประวัติการเข้าชม")),
        body: const Center(child: Text("กรุณาเข้าสู่ระบบเพื่อดูประวัติของคุณ")),
      );
    }

    final historysRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.email)
        .collection('historys')
        .orderBy('timestamp', descending: true);

    return WillPopScope(
      // ย้อนกลับไปหน้าหลัก
      onWillPop: () async {
        Navigator.push(
            context, MaterialPageRoute(builder: (context) => MainTabView()));
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("ประวัติการเข้าชม"),
          actions: [
            if (selectedHistorys.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _removeSelectedHistory,
              ),
            IconButton(
              icon: Icon(
                selectAll ? Icons.deselect : Icons.select_all,
                color: Colors.blue,
              ),
              onPressed: () async {
                // ดึงเอกสารทั้งหมดจาก Firestore
                final snapshot = await historysRef.get();
                List<String> allHistoryIds =
                snapshot.docs.map((doc) => doc.id).toList();
                _toggleSelectAll(allHistoryIds);
              },
            ),
          ],
        ),
        // ใช้ StreamBuilder เพื่อติดตามข้อมูลแบบ Real-time
        body: StreamBuilder<QuerySnapshot>(
          stream: historysRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(child: Text("เกิดข้อผิดพลาดในการโหลดประวัติการเข้าชม"));
            }

            final historys = snapshot.data?.docs ?? [];

            if (historys.isEmpty) {
              return const Center(child: Text("ไม่พบประวัติการเข้าชม"));
            }

            return ListView.builder(
              itemCount: historys.length,
              itemBuilder: (context, index) {
                final order = historys[index].data() as Map<String, dynamic>;
                final historyId = historys[index].id;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: ListTile(
                    leading: order['image'] != null
                        ? Image.network(
                      order['image'],
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.broken_image);
                      },
                    )
                        : const Icon(Icons.broken_image),
                    title: Text(order['title'] ?? 'No Title',
                        style: const TextStyle(fontSize: 14)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ราคา: ${order['price'] ?? 'Not Available'} บาท',
                            style:
                            const TextStyle(fontSize: 14, color: Colors.green)),

                        Text('แหล่งที่มาสินค้า: ${order['shop'] ?? 'Not Available'}',
                            style: const TextStyle(color: Colors.grey)),

                        Text('ความคุ่มค่า: ${order['value'] ?? 'Not Available'}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        Text(
                          order['timestamp'] != null
                              ? 'เข้าชมเมื่อ: ${DateFormat('dd/MM/yyyy HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(order['timestamp'].seconds * 1000).toLocal())}'
                              : 'เข้าชมเมื่อ: ไม่ระบุ',
                          style: const TextStyle(fontSize: 14, color: Colors.black),
                        ),

                        InkWell(
                          onTap: () async {
                            final url = order['url'];
                            if (url != null && url.isNotEmpty) {
                              final Uri uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("ไม่สามารถเปิดลิงก์ได้")),
                                );
                              }
                            }
                          },
                          child: Text(
                            "กดเพื่อดูสินค้าต้นทาง",
                            style: TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        selectedHistorys.contains(historyId)
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: selectedHistorys.contains(historyId)
                            ? Colors.green
                            : null,
                      ),
                      onPressed: () => _toggleSelection(historyId),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
