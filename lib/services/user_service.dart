import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum UserRole { parent, child }

extension UserRoleX on UserRole {
  String get value => this == UserRole.parent ? 'parent' : 'child';

  static UserRole fromValue(String? value) =>
      value == 'parent' ? UserRole.parent : UserRole.child;
}

/// Handles the extra Firestore data the Parent/Child Dashboard feature needs
/// on top of Firebase Auth: each account's role (parent/child) and the
/// parent<->child link.
///
/// Firestore shape:
///   users/{uid}: { role, email, createdAt, linkCode?, childIds[], parentIds[] }
///   users/{childUid}/sessions/{autoId}: session results (see SessionService)
class UserService {
  UserService._();
  static final instance = UserService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// Creates the user's Firestore profile the first time they log in or
  /// register. Safe to call every time - it only writes when the doc is
  /// missing, so it won't overwrite an existing role.
  Future<void> ensureUserDoc({UserRole? role}) async {
    final uid = currentUid;
    if (uid == null) return;
    final ref = _users.doc(uid);
    final snap = await ref.get();
    if (snap.exists) return;
    final effectiveRole = role ?? UserRole.child;
    final data = <String, dynamic>{
      'email': FirebaseAuth.instance.currentUser?.email,
      'role': effectiveRole.value,
      'createdAt': FieldValue.serverTimestamp(),
      'childIds': <String>[],
      'parentIds': <String>[],
    };
    if (effectiveRole == UserRole.child) {
      data['linkCode'] = _generateLinkCode();
    }
    await ref.set(data);
  }

  Future<UserRole> getRole(String uid) async {
    final snap = await _users.doc(uid).get();
    return UserRoleX.fromValue(snap.data()?['role'] as String?);
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final snap = await _users.doc(uid).get();
    return snap.data();
  }

  String _generateLinkCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Looks a child up by the 6-character code they share with a parent, and
  /// links the two accounts together in both directions. Returns the
  /// linked child's uid.
  Future<String> linkChildByCode(String code) async {
    final parentUid = currentUid;
    if (parentUid == null) throw Exception('Not signed in.');
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) throw Exception('Enter a code first.');
    final query = await _users
        .where('linkCode', isEqualTo: normalized)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw Exception('No child account found for that code.');
    }
    final childUid = query.docs.first.id;
    if (childUid == parentUid) {
      throw Exception('That is your own code.');
    }
    await _users.doc(parentUid).update({
      'childIds': FieldValue.arrayUnion([childUid]),
    });
    await _users.doc(childUid).update({
      'parentIds': FieldValue.arrayUnion([parentUid]),
    });
    return childUid;
  }

  Future<List<String>> getChildIds(String parentUid) async {
    final snap = await _users.doc(parentUid).get();
    final ids = snap.data()?['childIds'];
    if (ids is List) return ids.map((e) => e.toString()).toList();
    return [];
  }
}
