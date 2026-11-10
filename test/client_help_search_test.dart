import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/help/attorney_help_catalog.dart';
import 'package:law_connect4/help/client_help_search.dart';
import 'package:law_connect4/help/staff_help_catalog.dart';

void main() {
  const search = ClientHelpSearch();

  test('booking question returns the appointment guide', () {
    final matches = search.ask('unsaon pag book ug appointment');
    expect(matches, isNotEmpty);
    expect(matches.first.article.id, 'book-appointment');
  });

  test('billing words including bayad return billing', () {
    final matches = search.ask('asa ko mag bayad');
    expect(matches, isNotEmpty);
    expect(matches.first.article.id, 'billing');
  });

  test('unknown legal question does not invent an answer', () {
    expect(search.ask('unsa ang R.A. 10173'), isEmpty);
  });

  test('forgot password prefers the reset guide', () {
    final matches = search.ask('I forgot my password');
    expect(matches.first.article.id, 'forgot-password');
  });

  test('staff draft question stays on the draft guide', () {
    const staffSearch = ClientHelpSearch(articles: staffHelpArticles);
    final matches = staffSearch.ask('how do I create a draft case');
    expect(matches, isNotEmpty);
    expect(matches.first.article.id, 'staff-draft');
  });

  test('attorney appointment question stays on pending appointments', () {
    const attorneySearch = ClientHelpSearch(articles: attorneyHelpArticles);
    final matches = attorneySearch.ask('how do I accept an appointment');
    expect(matches, isNotEmpty);
    expect(matches.first.article.id, 'attorney-pending');
  });

  test('legal questions stay empty for staff and attorney', () {
    expect(
      const ClientHelpSearch(articles: staffHelpArticles).ask('R.A. 10173'),
      isEmpty,
    );
    expect(
      const ClientHelpSearch(
        articles: attorneyHelpArticles,
      ).ask('R.A. 10173'),
      isEmpty,
    );
  });
}