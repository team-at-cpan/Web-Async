widget comment_summary {
 :text "{{ comments.count }} total comments"
}
widget sort_by {
 :link uri: "#" display: "Sort by"
}
widget user_avatar(user) {
 :image uri: user.avatar.uri
}
widget comment_summary(comment) {
 :text "{{ comment.from.name }} to {{ comment.to.name }}"
}
widget comment_posted(comment) {
 :text "{{ comment.posted.date | relative_date }}"
}
widget comment_display(comment) {
 :text "{{ comment.content }}"
}
widget comment_actions(comment) {
 :link uri: "#" display: "Reply to this"
}
layout comment_post(comment) {
 :user_avatar user: comment.posted_by
 :comment_summary
 :comment_posted
 :comment_display
 :comment_actions
}
layout comment_body {
 each page.comments(comment) {
  :comment_post
 }
}
layout comment_header {
 :comment_summary comments: page.comments
 :sort_by
}
layout comments {
 :comment_header
 :comment_body
}
